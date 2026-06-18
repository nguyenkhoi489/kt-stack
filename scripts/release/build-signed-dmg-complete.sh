#!/bin/bash

set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)/../.."

echo "🔨 KTStack Complete DMG Build & Sign Pipeline"
echo "=============================================="

DEV_ID="${DEV_ID:-Developer ID Application: PHONG DA TRADING SERVICES COMPANY LIMITED (44452PW7V3)}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-kdwarm-notary}"

echo "ℹ️  Using identity: $DEV_ID"
echo "ℹ️  Keychain profile: $KEYCHAIN_PROFILE"

if ! security find-identity -v -p codesigning | grep -q "44452PW7V3"; then
    echo "❌ ERROR: Developer ID not found in keychain"
    echo "   Run: xcrun notarytool store-credentials $KEYCHAIN_PROFILE"
    exit 1
fi

echo ""
echo "📝 Step 1: Generate Xcode project"
xcodegen generate

echo ""
echo "🏗️  Step 2: Build app (Release)"
xcodebuild -project KDWarm.xcodeproj \
    -scheme KDWarm \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath .build-xcode \
    build

APP="$(find .build-xcode -name KTStack.app -path '*Release*' | head -1)"
if [ -z "$APP" ]; then
    echo "❌ ERROR: Built app not found"
    exit 1
fi
echo "✅ App found: $APP"

echo ""
echo "🔐 Step 3: Sign all binaries (inside-out)"
DEV_ID="$DEV_ID" scripts/release/sign-all-binaries.sh "$APP"
echo "✅ All binaries signed"

echo ""
echo "🔔 Step 4: Notarize app"
scripts/release/notarize.sh "$APP" "$KEYCHAIN_PROFILE"
echo "✅ App notarized & stapled"

echo ""
echo "📋 Step 5: License audit (generate NOTICES.txt)"
scripts/release/license-audit.sh

echo ""
echo "💿 Step 6: Build DMG"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="KTStack-$VERSION.dmg"

if [ -f "$DMG" ]; then
    echo "   Removing old DMG: $DMG"
    rm -f "$DMG"
fi

scripts/release/build-dmg.sh "$APP" "$DMG"
echo "✅ DMG created: $DMG"

echo ""
echo "🔐 Step 7: Sign DMG"
codesign --force --timestamp --sign "$DEV_ID" "$DMG"
echo "✅ DMG signed"

echo ""
echo "🔔 Step 8: Notarize DMG"
echo "   Submitting to Apple..."
xcrun notarytool submit "$DMG" --keychain-profile "$KEYCHAIN_PROFILE" --wait
echo "✅ DMG notarized"

echo ""
echo "📌 Step 9: Staple DMG"
xcrun stapler staple "$DMG"
echo "✅ DMG stapled"

echo ""
echo "✔️  Step 10: Verify signatures"
echo ""
echo "   --- App verification ---"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vvv "$APP" | head -5

echo ""
echo "   --- DMG verification ---"
codesign --verify --verbose=2 "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"

echo ""
echo "✅ SUCCESS! Ready to release:"
echo "   📦 $DMG"
echo ""
echo "Next steps:"
echo "  1. Upload to release server"
echo "  2. Update appcast (if using auto-update): scripts/release/update-appcast.sh <releases-dir>"
echo "  3. Announce release"
