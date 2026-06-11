#!/usr/bin/env bash
# S3 (PHP slice) — proves a static-php-cli PHP binary is relocatable: it runs from a
# MOVED app-support dir with no broken dylib path assumptions. This is the Phase-2 PHP
# half of S3 (nginx slice + the Phase-6 DB slice are tracked separately).
#
# Objective signal = otool -L (no non-system, non-@rpath absolute dylib refs) + the binary
# answering a health probe AFTER its containing dir is moved.
set -euo pipefail
cd "$(dirname "$0")"

PHP_VER="${PHP_VER:-8.4.8}"
TARBALL="php-${PHP_VER}-cli-macos-aarch64.tar.gz"
URL="https://dl.static-php.dev/static-php-cli/common/${TARBALL}"
STAGE="$PWD/staging"            # simulated ~/Library/Application Support/KDWarm/runtimes
MOVED="$PWD/staging-MOVED"      # where we relocate it to

rm -rf "$STAGE" "$MOVED"
mkdir -p "$STAGE/bin"

echo "=== download static PHP ${PHP_VER} (static-php-cli) ==="
curl -fsSL "$URL" -o "$STAGE/${TARBALL}"
tar -xzf "$STAGE/${TARBALL}" -C "$STAGE/bin"
PHP_BIN="$STAGE/bin/php"
chmod +x "$PHP_BIN"
[[ -x "$PHP_BIN" ]] || { echo "php binary not found after extract" >&2; ls -R "$STAGE/bin" >&2; exit 2; }

echo "=== otool -L (relocatability signal: only system /usr/lib + /System refs are safe) ==="
otool -L "$PHP_BIN"
BAD=$(otool -L "$PHP_BIN" | tail -n +2 | awk '{print $1}' \
        | grep -vE '^(/usr/lib/|/System/|@rpath/|@executable_path/|@loader_path/)' || true)
if [[ -n "$BAD" ]]; then
    echo "  ✗ non-relocatable dylib refs found:"; echo "$BAD" | sed 's/^/    /'
else
    echo "  ✓ no fragile absolute dylib refs (statically linked)"
fi

echo "=== health probe IN PLACE ==="
"$PHP_BIN" -v | head -1
INPLACE=$("$PHP_BIN" -r 'echo 6*7;')
echo "  php -r '6*7' => $INPLACE"

echo "=== MOVE the dir, then re-run from the moved path ==="
mv "$STAGE" "$MOVED"
MOVED_PHP="$MOVED/bin/php"
"$MOVED_PHP" -v | head -1
MOVEDOUT=$("$MOVED_PHP" -r 'echo 6*7;')
echo "  (moved) php -r '6*7' => $MOVEDOUT"

# --- gate ---
if [[ -z "$BAD" && "$INPLACE" == "42" && "$MOVEDOUT" == "42" ]]; then
    echo "S3-PHP PASS — static PHP ${PHP_VER} runs from a moved dir; otool clean."
    rm -rf "$MOVED"
    exit 0
else
    echo "S3-PHP FAIL — BAD='$BAD' inplace='$INPLACE' moved='$MOVEDOUT'"
    exit 1
fi
