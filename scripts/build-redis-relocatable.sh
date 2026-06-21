#!/usr/bin/env bash
# Build a relocatable redis-server from source and produce BOTH:
#   1) a dev copy in KTStack/Resources/bin/redis-server (so Phase 6's RedisController runs live), and
#   2) an on-demand artifact tar.gz + sha256 in .build-cache/artifacts/ (KTStack ships lean — DBs are
#      installed through the UI, not bundled; the artifact is what a release host serves).
#
# Relocatability: a default redis `make` links only system libs (/usr/lib, /System) + libSystem —
# no Homebrew/Cellar dylibs — so the binary runs from any install path. The otool gate enforces this.
# MALLOC=libc avoids the bundled jemalloc (keeps the link surface to system libs only).
#
# Licensing: Redis ≥7 is SSPL — KEPT for Laragon parity (free/open-source distribution is
# compatible); Phase 9 ships the NOTICE + source offer.
#
# Arch: host arch (arm64 on Apple Silicon). Universal is assembled in Phase 9 via lipo.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

REDIS_VER="${REDIS_VER:-7.4.2}"
ARCH="${ARCH:-$(uname -m)}"
OUT="${OUT:-$ROOT/KTStack/Resources/bin}"
ARTIFACTS="${ARTIFACTS:-$ROOT/.build-cache/artifacts}"
BUILD="${BUILD:-$ROOT/.build-cache/redis-$ARCH}"

echo "=== redis-server build — ${REDIS_VER} (${ARCH}) ==="
mkdir -p "$BUILD" "$OUT" "$ARTIFACTS"
cd "$BUILD"

SRC="redis-$REDIS_VER"
if [[ ! -d "$SRC" ]]; then
    echo "=== fetch redis source ==="
    curl -fsSL "https://download.redis.io/releases/redis-${REDIS_VER}.tar.gz" -o redis.tgz
    tar -xf redis.tgz
fi

echo "=== make (MALLOC=libc, no TLS, arch=${ARCH}) ==="
make -C "$SRC" -j"$(sysctl -n hw.ncpu)" MALLOC=libc BUILD_TLS=no \
    CFLAGS="-arch ${ARCH}" LDFLAGS="-arch ${ARCH}" >/dev/null
BIN="$BUILD/$SRC/src/redis-server"
[[ -x "$BIN" ]] || { echo "redis-server not produced at $BIN" >&2; exit 1; }

# shellcheck source=scripts/lib-relocatable.sh
source "$ROOT/scripts/lib-relocatable.sh"
relocatable_gate "$BIN"
ad_hoc_sign "$BIN"

cp "$BIN" "$OUT/redis-server"
ad_hoc_sign "$OUT/redis-server"
package_artifact "$OUT/redis-server" "redis" "$REDIS_VER" "bin/redis-server" "$ARTIFACTS"

echo "=== health probe ==="
"$OUT/redis-server" --version
echo "REDIS BUILD OK"
