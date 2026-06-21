#!/usr/bin/env bash
# Build a relocatable, TLS-capable nginx and vendor it into KTStack/Resources/bin.
#
# Relocatability technique (proven by the Foundations Spike, s3-relocatable/run-s3-nginx.sh):
# static-link OpenSSL + PCRE2 so no Homebrew Cellar dylib paths leak into the binary; let
# zlib resolve to the always-present system /usr/lib/libz. nginx bakes its prefix at compile
# time, but KTStack always launches it with a runtime `-p <app-support>` override, so the
# baked prefix is irrelevant — the binary runs from any install path.
#
# Arch scope: builds for the HOST arch by default (arm64 on Apple Silicon). The universal
# release binary is assembled in Phase 9 (packaging) by building each arch into a separate
# OUT_DIR and `lipo -create`-ing them; this script exposes ARCH + OUT so that step can drive it.
#
# Output: KTStack/Resources/bin/nginx (single-arch here; lipo'd to universal in Phase 9).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

NGX_VER="${NGX_VER:-1.27.4}"
ARCH="${ARCH:-$(uname -m)}"                       # arm64 | x86_64
OUT="${OUT:-$ROOT/KTStack/Resources/bin}"          # final vendor dir
BUILD="${BUILD:-$ROOT/.build-cache/nginx-$ARCH}"  # scratch (gitignored)

if [[ -z "${BREW:-}" ]]; then
    if [[ "$ARCH" == "x86_64" && "$(uname -m)" == "arm64" ]]; then
        BREW="arch -x86_64 /usr/local/bin/brew"
    elif [[ "$ARCH" == "x86_64" ]]; then
        BREW="/usr/local/bin/brew"
    else
        BREW="brew"
    fi
fi

SSL_PREFIX="$($BREW --prefix openssl@3)"
PCRE_PREFIX="$($BREW --prefix pcre2)"
SRC="$BUILD/src/nginx-${NGX_VER}"
PREFIX="$BUILD/nginx"
STATICLIBS="$BUILD/staticlibs"

echo "=== nginx ${NGX_VER} (${ARCH}) — relocatable build ==="
rm -rf "$BUILD"
mkdir -p "$BUILD/src" "$STATICLIBS" "$OUT"

# Isolate static archives so the linker is forced to pick .a (not the Cellar .dylib).
ln -sf "$SSL_PREFIX/lib/libssl.a"      "$STATICLIBS/libssl.a"
ln -sf "$SSL_PREFIX/lib/libcrypto.a"   "$STATICLIBS/libcrypto.a"
ln -sf "$PCRE_PREFIX/lib/libpcre2-8.a" "$STATICLIBS/libpcre2-8.a"

echo "=== download source ==="
curl -fsSL "https://nginx.org/download/nginx-${NGX_VER}.tar.gz" -o "$BUILD/src/nginx.tar.gz"
tar -xzf "$BUILD/src/nginx.tar.gz" -C "$BUILD/src"

echo "=== configure (static ssl/pcre2, system zlib, arch=${ARCH}) ==="
cd "$SRC"
./configure \
    --prefix="$PREFIX" \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_gzip_static_module \
    --with-http_sub_module \
    --with-cc-opt="-arch ${ARCH} -I$SSL_PREFIX/include -I$PCRE_PREFIX/include" \
    --with-ld-opt="-arch ${ARCH} -L$STATICLIBS" >/dev/null
echo "=== make ==="
make -j"$(sysctl -n hw.ncpu)" >/dev/null
make install >/dev/null
NGINX="$PREFIX/sbin/nginx"
cd "$ROOT"

echo "=== otool -L (relocatability gate) ==="
otool -L "$NGINX"
BAD=$(otool -L "$NGINX" | tail -n +2 | awk '{print $1}' \
        | grep -vE '^(/usr/lib/|/System/|@rpath/|@executable_path/|@loader_path/)' || true)
if [[ -n "$BAD" ]]; then
    echo "  ✗ leaked non-relocatable dylib refs:"; echo "$BAD" | sed 's/^/    /'; exit 1
fi
echo "  ✓ no fragile (Homebrew/Cellar) dylib refs"

cp "$NGINX" "$OUT/nginx"
chmod +x "$OUT/nginx"
# Ad-hoc sign so BinaryStager's `codesign --verify` passes in dev and the cdhash seals the
# binary against post-stage tampering. Phase 9 replaces this with a Developer ID signature.
codesign --force --sign - "$OUT/nginx"
echo "=== vendored → $OUT/nginx ($(lipo -archs "$OUT/nginx" 2>/dev/null || echo "$ARCH")) ==="
"$OUT/nginx" -V 2>&1 | head -1
echo "NGINX BUILD OK"
