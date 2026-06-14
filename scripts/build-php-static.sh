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

# NOTE: `mbregex` is a SEPARATE static-php-cli extension from `mbstring` (it links oniguruma) and
# provides the multibyte-regex functions — mb_split / mb_ereg* — that Laravel's Str helper calls.
# Without it mbstring loads but mb_split is undefined (fatal). Keep it alongside mbstring.
EXTENSIONS="${EXTENSIONS:-bcmath,bz2,calendar,curl,dom,event,exif,fileinfo,filter,gd,gmp,igbinary,intl,ldap,mbstring,mbregex,memcached,mysqli,opcache,openssl,pcntl,pdo,pdo_mysql,pdo_pgsql,pdo_sqlite,pgsql,phar,protobuf,readline,redis,session,snmp,soap,sockets,sqlite3,ssh2,sysvmsg,sysvshm,tokenizer,xhprof,xlswriter,xml,xsl,zip,zlib,zstd}"

# Optional install/uninstall extensions, built as relocatable shared objects (.so) OVER the same
# static base — they are NOT compiled into php; the version identity is unchanged. One artifact per
# (ext, version). Building these never alters the base php/php-fpm binaries (already packaged before
# this step), so an ext that fails to build never blocks shipping the base runtime. Set empty to skip.
# enchant is excluded: it is core-bundled in php-src (no standalone config.m4), so spc has no
# build-shared recipe for it — it belongs to the deferred/special-case track (like yaf/ioncube).
SHARED_EXTENSIONS="${SHARED_EXTENSIONS:-apcu,imagick,xdebug,grpc,swoole}"

# Where the ext artifacts will be hosted — used only to bake a resolvable download URL into the
# manifest fragment Phase 2's catalog consumes. Keep in sync with scripts/release/publish-artifacts.sh.
EXT_REPO="${EXT_REPO:-nguyenkhoi489/kd-warm}"
EXT_TAG="${EXT_TAG:-binaries-v1}"

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

# ── Optional shared extensions (install/uninstall .so layer) ──────────────────────────────────────
# spc emits buildroot/modules/<ext>.so per --build-shared ext, built against this same base. One ext
# that fails to build (or fails the relocatability gate) must NOT block the others or the base php
# artifact above — so failures are recorded to a sentinel file and this script still exits 0 (the base
# build succeeded). The dedicated ext wrapper (release/build-php-extensions.sh) is what turns a
# recorded ext failure into a non-zero verdict; keeping it out of here lets build-php-versions.sh build
# every base version without an unbuildable ext aborting the matrix.
FAILED_SENTINEL="$ARTIFACTS/php-ext-failed-$PHP_VER.txt"
rm -f "$FAILED_SENTINEL"
if [[ -n "$SHARED_EXTENSIONS" ]]; then
    echo ""
    echo "=== shared extensions: $SHARED_EXTENSIONS ==="
    IFS=',' read -ra _ext_list <<< "$SHARED_EXTENSIONS"

    MODULES="$BUILD/buildroot/modules"
    COLLECT="$BUILD/ext-collect"   # safe harbor — each retry's `make clean` wipes buildroot/modules
    mkdir -p "$MODULES" "$COLLECT"
    rm -f "$COLLECT"/*.so
    for ext in "${_ext_list[@]}"; do rm -f "$MODULES/$ext.so"; done

    # Copy any freshly-built .so out of buildroot/modules into COLLECT before the NEXT spc invocation
    # reinstalls the SAPI and wipes modules. Idempotent: only grabs wanted exts not already harvested.
    harvest_modules() {
        local e
        for e in "${_ext_list[@]}"; do
            [[ -f "$COLLECT/$e.so" ]] && continue
            [[ -f "$MODULES/$e.so" ]] && cp "$MODULES/$e.so" "$COLLECT/$e.so"
        done
        return 0   # never let a final false test (no .so yet) trip the caller's `set -e`
    }

    echo "=== download shared-ext deps ==="
    "$SPC" download --with-php="$PHP_VER" --for-extensions="$SHARED_EXTENSIONS" --prefer-pre-built

    # Fast path: one combined build pays the base recompile ONCE, then adds each ext via phpize in
    # seconds. spc aborts the whole batch at the first ext that fails to build, so any ext after the
    # failing one is skipped — the per-ext retry below rebuilds only those (each retry repeats the base
    # recompile + wipes modules, so we harvest after every build step). `|| echo` keeps a failed batch
    # from tripping `set -e`.
    echo "=== build shared .so (combined fast path) ==="
    "$SPC" build "$EXTENSIONS" --build-shared="$SHARED_EXTENSIONS" \
        || echo "  (combined build aborted early — retrying any missing ext individually)"
    harvest_modules

    for ext in "${_ext_list[@]}"; do
        [[ -f "$COLLECT/$ext.so" ]] && continue
        echo "=== retry shared build (isolated): $ext ==="
        "$SPC" build "$EXTENSIONS" --build-shared="$ext" || echo "  (✗ $ext failed to build shared)"
        harvest_modules
    done

    MANIFEST="$ARTIFACTS/php-ext-manifest-$PHP_VER.jsonl"   # one JSON object per ext, for Phase 2
    : > "$MANIFEST"
    EXT_FAILED=()
    for ext in "${_ext_list[@]}"; do
        echo ""
        echo "--- shared ext: $ext ---"
        so="$COLLECT/$ext.so"
        if [[ ! -f "$so" ]]; then
            echo "  ✗ $ext: not built (no $ext.so)"
            EXT_FAILED+=("$ext"); continue
        fi
        # Hard correctness gate: never package a .so that drags in non-system/absolute dylib refs.
        if ! relocatable_gate "$so"; then
            EXT_FAILED+=("$ext"); continue
        fi
        ad_hoc_sign "$so"
        # zend_extension for the debugger/profiler class (loaded at the Zend layer); plain extension
        # for everything else. Keep this list aligned with the Phase 2 catalog's loadDirective.
        case "$ext" in
            xdebug) load_directive="zend_extension" ;;
            *)      load_directive="extension" ;;
        esac
        package_extension "$so" "$ext" "$PHP_VER" "$ARTIFACTS"
        artifact="php-ext-${ext}-${PHP_VER}-${ARCH}.tar.gz"
        sha="$(awk '{print $1}' "$ARTIFACTS/$artifact.sha256")"
        url="https://github.com/$EXT_REPO/releases/download/$EXT_TAG/$artifact"
        printf '{"ext":"%s","version":"%s","artifact":"%s","url":"%s","sha256":"%s","loadDirective":"%s"}\n' \
            "$ext" "$PHP_VER" "$artifact" "$url" "$sha" "$load_directive" >> "$MANIFEST"
        echo "  ✓ $ext packaged ($load_directive)"
    done

    echo ""
    echo "=== shared-ext manifest ($PHP_VER) ==="
    cat "$MANIFEST"

    if [[ ${#EXT_FAILED[@]} -gt 0 ]]; then
        printf '%s\n' "${EXT_FAILED[@]}" > "$FAILED_SENTINEL"
        echo "⚠ shared exts FAILED on $PHP_VER: ${EXT_FAILED[*]} (base php + passing exts still produced)" >&2
    else
        echo "SHARED EXT BUILD OK ($PHP_VER): ${_ext_list[*]}"
    fi
fi
