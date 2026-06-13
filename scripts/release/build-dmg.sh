#!/usr/bin/env bash
# Build a distributable DMG from a (stapled) .app: a compressed image containing the app + an
# /Applications symlink for drag-install. Runnable on any Mac (no signing required to produce the
# image); for release, run it on the notarized+stapled app and optionally notarize the DMG too.
#
# Usage: scripts/release/build-dmg.sh <path-to-.app> [out.dmg]
set -euo pipefail
APP="${1:?usage: build-dmg.sh <path-to-.app> [out.dmg]}"
# Product name follows the .app bundle (survives a rebrand — no hardcoded "KDWarm" to drift).
NAME="$(basename "$APP" .app)"
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" \
    || { echo "could not read CFBundleShortVersionString from $APP" >&2; exit 1; }
OUT="${2:-$(dirname "$APP")/$NAME-$VER.dmg}"
STAGE="$(mktemp -d)/$NAME"
mkdir -p "$STAGE"

echo "=== stage DMG contents ==="
/usr/bin/ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
# Ship the attribution notices alongside the app if present.
[[ -f "$(dirname "$0")/../../NOTICES.txt" ]] && cp "$(dirname "$0")/../../NOTICES.txt" "$STAGE/"

echo "=== create compressed DMG → $OUT ==="
rm -f "$OUT"
hdiutil create -volname "$NAME $VER" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
rm -rf "$(dirname "$STAGE")"
echo "DMG: $OUT"
echo "(release: sign + notarize the .app first; optionally 'xcrun notarytool submit' + 'stapler staple' the DMG)"
