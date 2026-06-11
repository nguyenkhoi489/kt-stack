#!/usr/bin/env bash
# Notarize a signed KDWarm.app: zip it, submit to Apple, wait, then staple the ticket. Apple
# notarizes the bundle as a whole, so a single submission covers every nested signed binary —
# no per-binary submission needed. Run AFTER sign-all-binaries.sh, BEFORE build-dmg.sh.
#
# Auth: store credentials once with
#   xcrun notarytool store-credentials kdwarm-notary --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PW
# Usage: scripts/release/notarize.sh KDWarm.app [keychain-profile]
set -euo pipefail
APP="${1:?usage: notarize.sh <path-to-.app> [keychain-profile]}"
PROFILE="${2:-kdwarm-notary}"
ZIP="$(dirname "$APP")/$(basename "$APP" .app)-notarize.zip"

echo "=== zip the .app (ditto preserves signatures/symlinks) ==="
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "=== submit + wait ==="
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "=== staple the ticket to the .app ==="
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$ZIP"
echo "NOTARIZE OK — run scripts/release/build-dmg.sh next"
