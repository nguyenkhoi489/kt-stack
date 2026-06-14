#!/usr/bin/env bash
# Build the optional shared-extension (.so) artifacts across the PHP version matrix, then aggregate
# every per-version manifest fragment into one ext-manifest.json for the Phase-2 Swift catalog.
#
# Each version is built via build-php-static.sh with SHARED_EXTENSIONS set — that script also rebuilds
# the base php (cheap on a cached buildroot) and packages the base artifact, so this is a safe superset
# of a plain version build. A version whose ext build fails does NOT abort the matrix: failures are
# collected and reported at the end so a verification run surfaces every broken ext at once.
#
# Usage: scripts/release/build-php-extensions.sh [VER ...]      # default: 8.4 8.3 8.1
#   SHARED_EXTENSIONS=apcu,imagick scripts/release/build-php-extensions.sh 8.4   # subset / single ver
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"

VERSIONS=("$@")
[[ ${#VERSIONS[@]} -eq 0 ]] && VERSIONS=(8.4 8.3 8.1)

ARCH="${ARCH:-$(uname -m)}"
ARTIFACTS="${ARTIFACTS:-$ROOT/.build-cache/artifacts}"

echo "=== build shared extensions across versions: ${VERSIONS[*]} ==="
[[ -n "${SHARED_EXTENSIONS:-}" ]] && echo "    shared set (override): $SHARED_EXTENSIONS"

# Collected as "ver:ext" (or "ver:BASE-BUILD"). build-php-static.sh exits non-zero ONLY when the base
# php/fpm build fails; a per-ext failure is reported via its sentinel file and leaves exit 0, so we
# read the sentinels here to form this script's strict ext verdict.
FAILED_EXTS=()
for ver in "${VERSIONS[@]}"; do
    echo ""
    echo "######## PHP $ver — shared exts ########"
    if ! PHP_VER="$ver" bash "$ROOT/scripts/build-php-static.sh"; then
        FAILED_EXTS+=("$ver:BASE-BUILD")
        echo "  (base build failed for $ver — continuing matrix)"
        continue
    fi
    sentinel="$ARTIFACTS/php-ext-failed-$ver.txt"
    if [[ -s "$sentinel" ]]; then
        while read -r e; do [[ -n "$e" ]] && FAILED_EXTS+=("$ver:$e"); done < "$sentinel"
    fi
done

# ── Aggregate per-version JSONL fragments → one JSON array the Swift catalog can consume ──
MANIFEST_OUT="$ARTIFACTS/php-ext-manifest.json"
FRAGMENTS=("$ARTIFACTS"/php-ext-manifest-*.jsonl)
if [[ -e "${FRAGMENTS[0]}" ]]; then
    if command -v jq >/dev/null 2>&1; then
        jq -s '.' "${FRAGMENTS[@]}" > "$MANIFEST_OUT"
    else
        # jq-less fallback: wrap the concatenated JSONL lines into an array by hand.
        { echo "["; cat "${FRAGMENTS[@]}" | sed '$!s/$/,/'; echo "]"; } > "$MANIFEST_OUT"
    fi
    echo ""
    echo "=== aggregated ext manifest: $MANIFEST_OUT ==="
    cat "$MANIFEST_OUT"
else
    echo "WARNING: no per-version manifest fragments found under $ARTIFACTS" >&2
fi

# ── Publish hint ──
echo ""
echo "=== to publish the ext artifacts ==="
PUBLISH_LIST=()
for f in "$ARTIFACTS"/php-ext-*-"$ARCH".tar.gz; do
    [[ -e "$f" ]] && PUBLISH_LIST+=("$(basename "$f")")
done
if [[ ${#PUBLISH_LIST[@]} -gt 0 ]]; then
    echo "scripts/release/publish-artifacts.sh binaries-v1 ${PUBLISH_LIST[*]}"
else
    echo "(no ext artifacts produced)"
fi

if [[ ${#FAILED_EXTS[@]} -gt 0 ]]; then
    echo "" >&2
    echo "✗ shared-ext failures (ver:ext): ${FAILED_EXTS[*]}" >&2
    exit 1
fi
echo ""
echo "ALL SHARED EXT BUILDS OK: ${VERSIONS[*]}"
