#!/usr/bin/env bash
# Generate/refresh the Sparkle EdDSA-signed appcast from a folder of release artifacts (.dmg/.zip).
# Wraps Sparkle's `generate_appcast`, which computes the EdDSA signature for each update (using the
# private key stored in the Keychain by `generate_keys`) and writes/updates appcast.xml.
#
# Usage: scripts/release/update-appcast.sh <releases-dir>   # dir holding KDWarm-<ver>.dmg
# The EdDSA PRIVATE key must be in the Keychain (or pass --ed-key-file in CI); never commit it.
set -euo pipefail
RELEASES="${1:?usage: update-appcast.sh <releases-dir-with-dmgs>}"
DD="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"

# Prefer this project's resolved Sparkle (so the tool version matches the linked framework); fall
# back to any. Override with GENERATE_APPCAST=/path to pin explicitly in CI.
GEN_APPCAST="${GENERATE_APPCAST:-$(find "$DD"/KDWarm-* -path "*sparkle*/bin/generate_appcast" -type f 2>/dev/null | head -1)}"
[[ -x "${GEN_APPCAST:-}" ]] || GEN_APPCAST="$(find "$DD" -path "*sparkle*/bin/generate_appcast" -type f 2>/dev/null | head -1)"
[[ -x "$GEN_APPCAST" ]] || { echo "generate_appcast not found — build the app once so Sparkle resolves (or set DERIVED_DATA)." >&2; exit 1; }

echo "=== generate_appcast over $RELEASES ==="
"$GEN_APPCAST" "$RELEASES"
echo "appcast: $RELEASES/appcast.xml — publish it + the DMG to the SUFeedURL host over HTTPS."
