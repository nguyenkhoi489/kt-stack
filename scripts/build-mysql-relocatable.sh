#!/usr/bin/env bash
# Build a relocatable MySQL server (mysqld) from source and produce an on-demand artifact
# (tar.gz + sha256). MySQL ships on-demand (installed via the UI), so this does NOT copy into
# Resources/bin — it stages a self-contained mysql-<ver>/ tree (bin + lib + share) for a release host.
#
# HEAVY: CMake + a full C++ compile (bundled boost). Expect ~30-90 min and several GB of scratch.
# Run it directly when you want the artifact: `scripts/build-mysql-relocatable.sh`.
#
# Relocatability: mysqld derives its basedir from the executable path, so bin/share/lib kept together
# run from anywhere. The one external dep is OpenSSL (Homebrew) → vendored into lib/ + install names
# rewritten to @loader_path/../lib via `vendor_nonsystem_dylibs`. The build is re-extracted to a
# different path and `--initialize-insecure` is run to PROVE relocation.
#
# Licensing: MySQL is GPLv2 — KEPT for Laragon parity (free/open-source distribution is compatible);
# Phase 9 ships the NOTICE + written source offer. MariaDB remains a technically-swappable fallback.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

MYSQL_VER="${MYSQL_VER:-8.4.3}"
MYSQL_SERIES="${MYSQL_SERIES:-8.4}"
ARCH="${ARCH:-$(uname -m)}"
ARTIFACTS="${ARTIFACTS:-$ROOT/.build-cache/artifacts}"
BUILD="${BUILD:-$ROOT/.build-cache/mysql-$ARCH}"
PREFIX="$BUILD/buildroot"
source "$ROOT/scripts/lib-relocatable.sh"

command -v cmake >/dev/null || { echo "cmake required (brew install cmake)" >&2; exit 2; }
BREW="$(brew_for_arch)"
OPENSSL_PREFIX="${OPENSSL_PREFIX:-$($BREW --prefix openssl@3 2>/dev/null || true)}"
[[ -n "$OPENSSL_PREFIX" ]] || { echo "openssl@3 required (brew install openssl@3)" >&2; exit 2; }

echo "=== MySQL build — ${MYSQL_VER} (${ARCH}) — HEAVY, ~30-90 min ==="
mkdir -p "$BUILD" "$ARTIFACTS"
cd "$BUILD"

SRC="mysql-$MYSQL_VER"
if [[ ! -d "$SRC" ]]; then
    echo "=== fetch mysql source ($MYSQL_VER) ==="
    BASE="https://cdn.mysql.com/Downloads/MySQL-${MYSQL_SERIES}"
    # MySQL 8.x ships a bundled-boost source tarball; 9.x dropped it — fall back to the plain source
    # (cmake then downloads the matching boost itself, see DOWNLOAD_BOOST below).
    curl -fsSL "$BASE/mysql-boost-${MYSQL_VER}.tar.gz" -o mysql.tgz \
        || curl -fsSL "$BASE/mysql-${MYSQL_VER}.tar.gz" -o mysql.tgz
    tar -xf mysql.tgz
fi

if [[ ! -x "$PREFIX/bin/mysqld" ]]; then
    echo "=== cmake configure (minimal: no tests/router/mysqlx) ==="
    # Use the boost bundled in the source when present (8.x); otherwise let cmake fetch it (9.x).
    if [[ -d "$SRC/boost" ]]; then
        BOOST_FLAGS=(-DWITH_BOOST="$SRC/boost" -DDOWNLOAD_BOOST=0)
    else
        BOOST_FLAGS=(-DWITH_BOOST="$BUILD/boost-dl" -DDOWNLOAD_BOOST=1)
    fi
    XLIB_FLAGS=()
    if [[ "$ARCH" != "$(uname -m)" ]]; then
        XLIB_FLAGS=(-DWITH_ZSTD=system -DWITH_LZ4=system
                    -DCMAKE_PREFIX_PATH="$($BREW --prefix zstd);$($BREW --prefix lz4)")
    fi
    cmake -S "$SRC" -B "$BUILD/cmbuild" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DCMAKE_SYSTEM_PROCESSOR="$ARCH" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        "${BOOST_FLAGS[@]}" "${XLIB_FLAGS[@]}" \
        -DWITH_SSL="$OPENSSL_PREFIX" \
        -DWITH_UNIT_TESTS=OFF -DWITH_ROUTER=OFF -DWITH_MYSQLX=OFF >/dev/null
    echo "=== make + install (this is the long part) ==="
    cmake --build "$BUILD/cmbuild" -j"$(sysctl -n hw.ncpu)" >/dev/null
    cmake --install "$BUILD/cmbuild" >/dev/null
fi

echo "=== stage self-contained artifact tree ==="
STAGE="$(mktemp -d)"; TOP="$STAGE/mysql-$MYSQL_VER"
mkdir -p "$TOP"
cp -R "$PREFIX/bin" "$TOP/bin"
cp -R "$PREFIX/lib" "$TOP/lib"
cp -R "$PREFIX/share" "$TOP/share"

echo "=== vendor OpenSSL + fix install names (ALL bin tools, not just mysqld) ==="
# The client tools (mysql, mysqldump, …) link OpenSSL by absolute Homebrew path too — vendor every
# Mach-O so the whole tree is relocatable AND same-team-signable under Hardened Runtime (an external
# Homebrew dylib is rejected by library validation once the tool is Developer-ID signed).
for b in "$TOP"/bin/*; do
    file -b "$b" | grep -q "Mach-O" || continue
    vendor_nonsystem_dylibs "$b" "$TOP/lib"
done

# Plugins live in lib/plugin/, so they reach the vendored OpenSSL in lib/ via @loader_path/.. (one
# level up) — NOT ../lib (which from lib/plugin would resolve to lib/lib). Vendor + rewrite them here.
for p in "$TOP"/lib/plugin/*.so; do
    [[ -e "$p" ]] || continue
    file -b "$p" | grep -q "Mach-O" || continue
    while IFS= read -r ref; do
        case "$ref" in /usr/lib/*|/System/*|@*) continue ;; esac
        base="$(basename "$ref")"
        [[ -f "$TOP/lib/$base" ]] || cp "$ref" "$TOP/lib/$base" 2>/dev/null || continue
        install_name_tool -change "$ref" "@loader_path/../$base" "$p" 2>/dev/null || true
    done < <(otool -L "$p" | tail -n +2 | awk '{print $1}')
done

echo "=== relocatability gate (every bin tool + plugin) ==="
for b in "$TOP"/bin/* "$TOP"/lib/plugin/*.so; do
    [[ -e "$b" ]] || continue
    file -b "$b" | grep -q "Mach-O" || continue
    relocatable_gate "$b"
done
ad_hoc_sign "$TOP/bin/mysqld" "$TOP"/lib/*.dylib 2>/dev/null || ad_hoc_sign "$TOP/bin/mysqld"

echo "=== PROVE relocation: --initialize-insecure from a moved copy ==="
RELOC="$(mktemp -d)/moved"; mkdir -p "$RELOC"; cp -R "$TOP" "$RELOC/"
MYDIR="$RELOC/mysql-$MYSQL_VER"; DATA="$(mktemp -d)/data"
if "$MYDIR/bin/mysqld" --no-defaults --initialize-insecure --datadir="$DATA" >/tmp/mysql-reloc.log 2>&1; then
    echo "  ✓ mysqld initialized from moved path"
else
    echo "  ✗ mysqld failed from moved path:"; tail -8 /tmp/mysql-reloc.log; exit 1
fi
rm -rf "$DATA" "$RELOC"

package_dir "$TOP" "$ARTIFACTS"
rm -rf "$STAGE"
echo "MYSQL BUILD OK"
