#!/usr/bin/env bash
# Build a relocatable PostgreSQL (server + initdb) from source and produce an on-demand artifact
# (tar.gz + sha256). PostgreSQL ships on-demand (installed via the UI), so this does NOT copy into
# KDWarm/Resources/bin — it stages a self-contained postgres-<ver>/ tree (bin + lib + share) that a
# release host serves and the downloader extracts into runtimes/postgres/<ver>/.
#
# Relocatability: postgres locates its support files (share/, lib/) relative to the executable
# (`find_my_exec`), so a self-contained bin/lib/share tree runs from any path. The only absolute
# refs are libpq/libpgport install names → rewritten to @loader_path/../lib here. Homebrew deps are
# excluded at configure time (--without-icu/readline/zlib/lz4/zstd/openssl) to keep the link surface
# to system libs. The build is then re-extracted to a DIFFERENT path and run to PROVE relocation.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

PG_VER="${PG_VER:-17.10}"
ARCH="${ARCH:-$(uname -m)}"
ARTIFACTS="${ARTIFACTS:-$ROOT/.build-cache/artifacts}"
BUILD="${BUILD:-$ROOT/.build-cache/postgres-$ARCH}"
PREFIX="$BUILD/buildroot"
source "$ROOT/scripts/lib-relocatable.sh"

echo "=== PostgreSQL build — ${PG_VER} (${ARCH}) ==="
mkdir -p "$BUILD" "$ARTIFACTS"
cd "$BUILD"

SRC="postgresql-$PG_VER"
if [[ ! -d "$SRC" ]]; then
    echo "=== fetch postgres source ==="
    curl -fsSL "https://ftp.postgresql.org/pub/source/v${PG_VER}/postgresql-${PG_VER}.tar.gz" -o pg.tgz
    tar -xf pg.tgz
fi

if [[ ! -x "$PREFIX/bin/postgres" ]]; then
    echo "=== configure (system-libs only) ==="
    ( cd "$SRC" && ./configure --prefix="$PREFIX" \
        --without-icu --without-readline --without-zlib \
        --without-lz4 --without-zstd --without-openssl >/dev/null )
    echo "=== make + install ==="
    make -C "$SRC" -j"$(sysctl -n hw.ncpu)" >/dev/null
    make -C "$SRC" install >/dev/null
fi

echo "=== rewrite dylib install names → @loader_path/../lib ==="
for dylib in "$PREFIX"/lib/*.dylib; do
    [[ -e "$dylib" ]] || continue
    install_name_tool -id "@loader_path/../lib/$(basename "$dylib")" "$dylib" 2>/dev/null || true
done
# Repoint each executable's libpq/libpgtypes references to the relative path + add an rpath.
for exe in "$PREFIX"/bin/*; do
    [[ -x "$exe" && ! -d "$exe" ]] || continue
    while read -r ref; do
        case "$ref" in
            "$PREFIX"/lib/*) install_name_tool -change "$ref" "@loader_path/../lib/$(basename "$ref")" "$exe" 2>/dev/null || true ;;
        esac
    done < <(otool -L "$exe" | tail -n +2 | awk '{print $1}')
    install_name_tool -add_rpath "@loader_path/../lib" "$exe" 2>/dev/null || true
done

echo "=== stage self-contained artifact tree ==="
STAGE="$(mktemp -d)"; TOP="$STAGE/postgres-$PG_VER"
mkdir -p "$TOP"
cp -R "$PREFIX/bin" "$TOP/bin"
cp -R "$PREFIX/lib" "$TOP/lib"
cp -R "$PREFIX/share" "$TOP/share"

echo "=== relocatability gate (server + initdb + backup client tools) ==="
CLIENT_TOOLS=(postgres initdb pg_dump pg_restore createdb dropdb psql)
SIGN_TARGETS=()
for tool in "${CLIENT_TOOLS[@]}"; do
    relocatable_gate "$TOP/bin/$tool"
    SIGN_TARGETS+=("$TOP/bin/$tool")
done
ad_hoc_sign "${SIGN_TARGETS[@]}" "$TOP"/lib/*.dylib

echo "=== PROVE relocation: run initdb + postgres from a moved copy ==="
RELOC="$(mktemp -d)/moved"; mkdir -p "$RELOC"; cp -R "$TOP" "$RELOC/"
PGDIR="$RELOC/postgres-$PG_VER"; DATA="$(mktemp -d)/data"
"$PGDIR/bin/initdb" -D "$DATA" -U postgres --auth=trust -E UTF8 >/dev/null
"$PGDIR/bin/postgres" -D "$DATA" -p 55432 -c listen_addresses=127.0.0.1 >/tmp/pg-reloc.log 2>&1 &
PGPID=$!; sleep 3
if kill -0 "$PGPID" 2>/dev/null; then echo "  ✓ postgres started from moved path (pid $PGPID)"; kill "$PGPID"; wait "$PGPID" 2>/dev/null || true
else echo "  ✗ postgres failed from moved path:"; tail -5 /tmp/pg-reloc.log; exit 1; fi
for tool in pg_dump pg_restore createdb dropdb psql; do
    if "$PGDIR/bin/$tool" --version >/dev/null 2>&1; then echo "  ✓ $tool runs from moved path"
    else echo "  ✗ $tool failed from moved path"; exit 1; fi
done
rm -rf "$DATA" "$RELOC"

package_dir "$TOP" "$ARTIFACTS"
rm -rf "$STAGE"
echo "POSTGRES BUILD OK"
