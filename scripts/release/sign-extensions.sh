#!/usr/bin/env bash
# Developer-ID-sign + re-package the optional-extension `.so` artifacts for production (Phase 9).
#
# The build pipeline (build-php-static.sh) only AD-HOC signs each `.so` — fine on the un-notarized dev
# build, but a notarized, hardened php-fpm runs ONLY a `.so` signed by the SAME Team ID (macOS Library
# Validation rejects a foreign-team `.so`). So before a production publish each `.so` must be re-signed
# with the same Developer ID as php-fpm. A `.so` is a LOADED library, not a process → codesign
# entitlements do not apply to it (ignored for a non-main-executable Mach-O); what matters is the Team
# ID + hardened-runtime flag + secure timestamp. Do NOT grant php-fpm `disable-library-validation` —
# same-Team signing IS the defense against a third party dropping a `.so`.
#
# Re-signing changes each `.so`'s sha256 → the tar.gz is re-packaged and its hash re-emitted; bump
# those into KDWarmKit/Sources/Runtimes/PHPExtensionManifest.swift, notarize each artifact, publish
# --clobber, then rebuild the app (same gotcha as the runtime artifacts — see the signing guide §4).
#
# Run AFTER scripts/release/build-php-extensions.sh has produced .build-cache/php-arm64-<ver>/ext-collect.
# Usage: DEV_ID="Developer ID Application: … (TEAMID)" scripts/release/sign-extensions.sh [VER ...]
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
source "$ROOT/scripts/lib-relocatable.sh"

DEV_ID="${DEV_ID:?set DEV_ID to your 'Developer ID Application: …' identity}"
ARCH="${ARCH:-$(uname -m)}"
ARTIFACTS="${ARTIFACTS:-$ROOT/.build-cache/artifacts}"
EXT_REPO="${EXT_REPO:-nguyenkhoi489/kd-warm}"
EXT_TAG="${EXT_TAG:-binaries-v1}"
VERSIONS=("$@")
[[ ${#VERSIONS[@]} -eq 0 ]] && VERSIONS=(8.4 8.3 8.1)

mkdir -p "$ARTIFACTS"
FRAG="$ARTIFACTS/php-ext-manifest-signed.jsonl"; : > "$FRAG"

for ver in "${VERSIONS[@]}"; do
    COLLECT="$ROOT/.build-cache/php-arm64-$ver/ext-collect"
    [[ -d "$COLLECT" ]] || { echo "skip $ver — no ext-collect (run build-php-extensions.sh first)"; continue; }
    for so in "$COLLECT"/*.so; do
        [[ -e "$so" ]] || continue
        ext="$(basename "$so" .so)"
        echo "=== Developer-ID sign $ext ($ver) ==="
        codesign --force --options runtime --timestamp --sign "$DEV_ID" "$so"
        relocatable_gate "$so"                 # re-confirm clean after signing
        codesign --verify --strict --verbose=1 "$so"
        package_extension "$so" "$ext" "$ver" "$ARTIFACTS"
        artifact="php-ext-${ext}-${ver}-${ARCH}.tar.gz"
        sha="$(awk '{print $1}' "$ARTIFACTS/$artifact.sha256")"
        case "$ext" in xdebug) ld="zend_extension" ;; *) ld="extension" ;; esac
        printf '{"ext":"%s","version":"%s","artifact":"%s","url":"https://github.com/%s/releases/download/%s/%s","sha256":"%s","loadDirective":"%s"}\n' \
            "$ext" "$ver" "$artifact" "$EXT_REPO" "$EXT_TAG" "$artifact" "$sha" "$ld" >> "$FRAG"
    done
done

MANIFEST="$ARTIFACTS/php-ext-manifest.json"
if command -v jq >/dev/null 2>&1; then jq -s '.' "$FRAG" > "$MANIFEST"
else { echo "["; sed '$!s/$/,/' "$FRAG"; echo "]"; } > "$MANIFEST"; fi
rm -f "$FRAG"

echo ""
echo "=== re-signed manifest — bump these sha256 into PHPExtensionManifest.swift ==="
cat "$MANIFEST"
echo ""
echo "=== then notarize each + publish (clobber), like the runtime artifacts (guide §4) ==="
echo "for f in $ARTIFACTS/php-ext-*-$ARCH.tar.gz; do xcrun notarytool submit \"\$f\" --keychain-profile kdwarm-notary --wait; done"
PUB=(); for f in "$ARTIFACTS"/php-ext-*-"$ARCH".tar.gz; do [[ -e "$f" ]] && PUB+=("$(basename "$f")"); done
echo "scripts/release/publish-artifacts.sh binaries-v1 ${PUB[*]}"
