#!/usr/bin/env bash
# Build a relocatable, statically-linked PHP (cli + php-fpm) via static-php-cli (spc) and package it
# as an on-demand artifact (tar.gz + sha256). No PHP is vendored into the app bundle — every version
# installs on demand from the hosted GitHub Release.
#
# Why static-php-cli: it produces a self-contained PHP with no Cellar/Homebrew dylib
# dependencies (otool shows only system /usr/lib + /System frameworks) — proven relocatable
# by the Foundations Spike (s3-relocatable/run-s3-php.sh). The prebuilt downloads at
# dl.static-php.dev ship the CLI only, so php-fpm MUST be compiled here.
#
# Extension set: a curated, comprehensive web-dev matrix so most projects run without a missing
# extension. Static PHP can't dlopen at runtime, so the set is fixed at build time — adding one is a
# rebuild + re-publish, never a user action. Heavy deps (gd→libpng/jpeg/freetype, intl→ICU,
# zip→libzip, gmp, bz2) inflate build time + binary size; imagick is excluded (ImageMagick isn't
# static-friendly). static-php-cli resolves each extension's libs via `download --for-extensions`.
#
# JIT: opcache is included → PHP's JIT is available (opcache.jit). This requires the
# `com.apple.security.cs.allow-jit` entitlement once the app is notarized — RECORDED for
# Phase 9 (this dev build is un-notarized so JIT runs without it).
#
# Arch scope: builds for the HOST arch (arm64 on Apple Silicon). Universal is assembled in
# Phase 9 by building each arch and `lipo -create`-ing the results.
#
# Output: .build-cache/artifacts/php-<ver>-arm64.tar.gz (+ .sha256)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

PHP_VER="${PHP_VER:-8.4}"
ARCH="${ARCH:-$(uname -m)}"                    # arm64 | x86_64 (spc target token below)
OUT="${OUT:-$ROOT/KDWarm/Resources/bin}"
BUILD="${BUILD:-$ROOT/.build-cache/php-$ARCH-$PHP_VER}" # per-version scratch (gitignored) — must NOT
                                                       # be shared across versions or a stale buildroot
                                                       # leaks the wrong PHP into the artifact.

# spc arch token: arm64 → aarch64
case "$ARCH" in
  arm64)  SPC_ARCH="aarch64" ;;
  x86_64) SPC_ARCH="x86_64" ;;
  *) echo "unsupported ARCH=$ARCH" >&2; exit 2 ;;
esac

EXTENSIONS="${EXTENSIONS:-bcmath,bz2,calendar,curl,dom,exif,fileinfo,filter,gd,gmp,intl,mbstring,mysqli,opcache,openssl,pcntl,pdo,pdo_mysql,pdo_sqlite,phar,redis,session,soap,sockets,sqlite3,tokenizer,xml,zip,zlib}"

echo "=== static-php-cli build — PHP ${PHP_VER} (${ARCH}) ==="
echo "    extensions: $EXTENSIONS"
mkdir -p "$BUILD" "$OUT"
cd "$BUILD"

SPC="$BUILD/spc"
if [[ ! -x "$SPC" ]]; then
    echo "=== fetch spc (static-php-cli) ==="
    curl -fsSL "https://dl.static-php.dev/static-php-cli/spc-bin/nightly/spc-macos-${SPC_ARCH}" -o "$SPC"
    chmod +x "$SPC"
fi
"$SPC" --version

echo "=== doctor (auto-fix build prerequisites) ==="
"$SPC" doctor --auto-fix

echo "=== download PHP ${PHP_VER} source + extension deps ==="
"$SPC" download --with-php="$PHP_VER" --for-extensions="$EXTENSIONS" --prefer-pre-built

echo "=== build (cli + fpm), static ==="
"$SPC" build "$EXTENSIONS" --build-cli --build-fpm

PHP_BIN="$BUILD/buildroot/bin/php"
# static-php-cli stages php-fpm in buildroot/bin (not sbin).
FPM_BIN="$BUILD/buildroot/bin/php-fpm"
[[ -x "$PHP_BIN" ]] || { echo "php not produced at $PHP_BIN" >&2; ls -R "$BUILD/buildroot" >&2; exit 1; }
[[ -x "$FPM_BIN" ]] || { echo "php-fpm not produced at $FPM_BIN" >&2; ls -R "$BUILD/buildroot" >&2; exit 1; }

echo "=== otool -L (relocatability gate) ==="
for b in "$PHP_BIN" "$FPM_BIN"; do
    otool -L "$b"
    BAD=$(otool -L "$b" | tail -n +2 | awk '{print $1}' \
            | grep -vE '^(/usr/lib/|/System/|@rpath/|@executable_path/|@loader_path/)' || true)
    [[ -z "$BAD" ]] || { echo "  ✗ leaked dylib refs in $(basename "$b"):"; echo "$BAD" | sed 's/^/    /'; exit 1; }
    echo "  ✓ $(basename "$b") clean"
done

# Ad-hoc sign so the cdhash seals the binary against post-stage tampering (Phase 9 → Developer ID).
codesign --force --sign - "$PHP_BIN" "$FPM_BIN"

echo "=== health probe ==="
"$PHP_BIN" -v | head -1
echo "  php -r '6*7' => $("$PHP_BIN" -r 'echo 6*7;')"

# Every PHP version (incl. the default 8.4) installs ON-DEMAND from the hosted GitHub Release — the
# app ships NO PHP in Resources/bin, keeping the DMG lean. Each version is produced only as a hosted
# artifact below; nothing is copied flat into the bundle.

# On-demand artifact: php-<ver>/bin/{php,php-fpm} → tar.gz + sha256 (downloader extract layout).
echo "=== package on-demand artifact ==="
source "$ROOT/scripts/lib-relocatable.sh"
STAGE="$(mktemp -d)"; TOP="$STAGE/php-$PHP_VER"; mkdir -p "$TOP/bin"
cp "$PHP_BIN" "$TOP/bin/php"; cp "$FPM_BIN" "$TOP/bin/php-fpm"
ARTIFACTS="${ARTIFACTS:-$ROOT/.build-cache/artifacts}"
package_dir "$TOP" "$ARTIFACTS"
rm -rf "$STAGE"
echo "PHP BUILD OK"
