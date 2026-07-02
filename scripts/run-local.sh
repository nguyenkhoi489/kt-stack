#!/usr/bin/env bash
# Build + run KTStack.app locally for testing WITHOUT a Developer ID. A Hardened-Runtime app with
# ad-hoc-signed embedded frameworks fails library validation, so after building we re-sign the app
# ad-hoc with `disable-library-validation` (local test ONLY — the release build uses a real
# Developer ID via scripts/release/sign-all-binaries.sh and does not need this).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== regenerate project + build (Release) ==="
xcodegen generate >/dev/null
xcodebuild -project KTStack.xcodeproj -scheme KTStack -configuration Release \
    -destination 'platform=macOS' build >/tmp/ktstack-build.log 2>&1 \
    || { echo "build failed — see /tmp/ktstack-build.log"; tail -20 /tmp/ktstack-build.log; exit 1; }

APP="$(find "$HOME/Library/Developer/Xcode/DerivedData"/KTStack-*/Build/Products/Release \
    -maxdepth 1 -name KTStack.app | head -1)"
[[ -d "$APP" ]] || { echo "KTStack.app not found"; exit 1; }
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
codesign --force --sign - "$APP/Contents/Frameworks/KTStackKit.framework"
codesign --force --sign - --deep "$APP/Contents/Frameworks/Sparkle.framework"
# Re-sign bundled bin/ binaries. The repo copies are ad-hoc "not signed at all" per codesign on
# macOS 26, so BinaryStager.enforceSignature (codesign --verify --strict) rejects them and the web
# server never starts. A fresh ad-hoc sign produces a signature verify accepts. Release uses
# scripts/release/sign-all-binaries.sh with a real Developer ID; this is local-only.
find "$APP/Contents/Resources/bin" -type f -perm +111 -exec codesign --force --sign - {} \;
codesign --force --sign - --options runtime --entitlements "$ENT" "$APP"
rm -f "$ENT"

# A previous crash can leave a window-restoration state that re-opens (and re-crashes) a window.
rm -rf "$HOME/Library/Saved Application State/com.ktstack.app.savedState" 2>/dev/null || true

echo "=== launch ==="
pkill -f "KTStack.app/Contents/MacOS/KTStack" 2>/dev/null || true
sleep 1
open "$APP"
sleep 3
pgrep -f "KTStack.app/Contents/MacOS/KTStack" >/dev/null \
    && echo "✅ KTStack is running — look for the bolt icon in the menu bar." \
    || { echo "❌ not running — last crash:"; ls -t "$HOME/Library/Logs/DiagnosticReports"/KTStack*.ips 2>/dev/null | head -1; }
