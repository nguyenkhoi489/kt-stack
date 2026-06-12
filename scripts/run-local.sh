#!/usr/bin/env bash
# Build + run KDWarm.app locally for testing WITHOUT a Developer ID. A Hardened-Runtime app with
# ad-hoc-signed embedded frameworks fails library validation, so after building we re-sign the app
# ad-hoc with `disable-library-validation` (local test ONLY — the release build uses a real
# Developer ID via scripts/release/sign-all-binaries.sh and does not need this).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== regenerate project + build (Release) ==="
xcodegen generate >/dev/null
xcodebuild -project KDWarm.xcodeproj -scheme KDWarm -configuration Release \
    -destination 'platform=macOS' build >/tmp/kdwarm-build.log 2>&1 \
    || { echo "build failed — see /tmp/kdwarm-build.log"; tail -20 /tmp/kdwarm-build.log; exit 1; }

APP="$(find "$HOME/Library/Developer/Xcode/DerivedData"/KDWarm-*/Build/Products/Release \
    -maxdepth 1 -name KDWarm.app | head -1)"
[[ -d "$APP" ]] || { echo "KDWarm.app not found"; exit 1; }
echo "app: $APP"

echo "=== re-sign ad-hoc for local run (disable-library-validation) ==="
ENT="$(mktemp).entitlements"
cat > "$ENT" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><false/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$APP/Contents/Frameworks/KDWarmKit.framework"
codesign --force --sign - --deep "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --options runtime --entitlements "$ENT" "$APP"
rm -f "$ENT"

# A previous crash can leave a window-restoration state that re-opens (and re-crashes) a window.
rm -rf "$HOME/Library/Saved Application State/com.kdwarm.app.savedState" 2>/dev/null || true

echo "=== launch ==="
pkill -f "KDWarm.app/Contents/MacOS/KDWarm" 2>/dev/null || true
sleep 1
open "$APP"
sleep 3
pgrep -f "KDWarm.app/Contents/MacOS/KDWarm" >/dev/null \
    && echo "✅ KDWarm is running — look for the bolt icon in the menu bar." \
    || { echo "❌ not running — last crash:"; ls -t "$HOME/Library/Logs/DiagnosticReports"/KDWarm*.ips 2>/dev/null | head -1; }
