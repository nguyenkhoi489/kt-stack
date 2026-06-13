#!/usr/bin/env bash
# Make a LOCAL ad-hoc Release build runnable on this Mac (no Developer ID needed).
#
# Why this exists: a Release build runs under Hardened Runtime, which enforces Library Validation —
# every embedded framework must share the main executable's Team ID. Ad-hoc signatures have no stable
# Team ID, so LaunchServices ("open") rejects the app with "different Team IDs" and dyld aborts at
# launch. (Debug builds escape this via the get-task-allow entitlement.) This re-signs the bundle
# inside-out and adds `disable-library-validation` to the APP ONLY, so the local copy loads.
#
# Scope: LOCAL RUN ONLY. It does NOT touch the committed entitlements — production posture (Library
# Validation ON) is unchanged. For real distribution use `sign-all-binaries.sh` + `notarize.sh` with a
# Developer ID: a consistent Team ID makes Library Validation pass with NO entitlement relaxation.
#
# Usage: scripts/release/sign-local-run.sh <path-to-.app>
set -euo pipefail
APP="${1:?usage: sign-local-run.sh <path-to-.app>}"
[[ -d "$APP" ]] || { echo "not a bundle: $APP" >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Local entitlements = the committed app entitlements + disable-library-validation (so it stays in
# sync with what ships, minus the one relaxation needed to run ad-hoc locally). Written to a temp
# file, never into the repo.
ENT="$(mktemp -t kt-local-run).entitlements"
trap 'rm -f "$ENT"' EXIT
cp "$ROOT/entitlements/app.entitlements" "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENT" \
  >/dev/null 2>&1 || true   # already present on a re-run → ignore

echo "=== sign nested code inside-out (frameworks first) ==="
# Sign every embedded framework's current version, keeping Hardened Runtime.
find "$APP/Contents/Frameworks" -type d -name "*.framework" 2>/dev/null | while read -r fw; do
  echo "  sign $(basename "$fw")"
  codesign --force --options runtime --sign - "$fw"
done

echo "=== sign the app (last, with library validation disabled for local run) ==="
codesign --force --options runtime --entitlements "$ENT" --sign - "$APP"

echo "=== verify ==="
codesign --verify --deep --strict --verbose=2 "$APP"
echo "OK — $APP is runnable locally (ad-hoc, library validation disabled for this copy only)."
