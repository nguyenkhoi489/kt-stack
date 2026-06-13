#!/usr/bin/env bash
# Publish the self-built, relocatable runtime/engine artifacts (PHP, Redis, Postgres) to a GitHub
# Release so the in-app on-demand installer can download them. php.net / Redis / Postgres ship no
# relocatable macOS arm64 drop-in, so KDWarm builds its own (scripts/build-*.sh) and hosts them here;
# the manifests in RuntimeCatalog.swift / ServiceBinaryCatalog.swift point at this Release's assets.
#
# Idempotent: re-running re-uploads (--clobber) the listed assets to the same tag.
#
# Usage: scripts/release/publish-artifacts.sh [TAG] [artifact ...]
#   TAG        defaults to "binaries-v1" (must match the URLs baked into the Swift manifests)
#   artifact   one or more .tar.gz under .build-cache/artifacts; defaults to the published set below
#
# Requires: gh (authenticated to the repo), shasum.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"

REPO="nguyenkhoi489/kd-warm"
TAG="${1:-binaries-v1}"; shift || true
ART_DIR="$ROOT/.build-cache/artifacts"

# Default published set — keep in sync with the Swift manifests. Add php-7.4 here if/when it builds
# (it is EOL and currently fails under static-php-cli).
DEFAULT_ARTIFACTS=(
  "php-8.4-arm64.tar.gz"
  "php-8.3-arm64.tar.gz"
  "php-8.1-arm64.tar.gz"
  "mysql-9.6.0-arm64.tar.gz"
  "redis-7.4.2-arm64.tar.gz"
  "postgres-17.10-arm64.tar.gz"
)
ARTIFACTS=("$@")
[[ ${#ARTIFACTS[@]} -eq 0 ]] && ARTIFACTS=("${DEFAULT_ARTIFACTS[@]}")

command -v gh >/dev/null || { echo "ERROR: gh not found"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh not authenticated"; exit 1; }

echo "=== Publishing ${#ARTIFACTS[@]} artifact(s) to $REPO @ $TAG ==="

# Verify every artifact exists + emit a .sha256 sidecar (so a manual/curl download can self-verify).
UPLOADS=()
for name in "${ARTIFACTS[@]}"; do
  file="$ART_DIR/$name"
  [[ -f "$file" ]] || { echo "ERROR: missing artifact $file (build it first)"; exit 1; }
  ( cd "$ART_DIR" && shasum -a 256 "$name" > "$name.sha256" )
  echo "  $name  sha256=$(awk '{print $1}' "$file.sha256")"
  UPLOADS+=("$file" "$file.sha256")
done

# Create the release once; thereafter just upload assets to it.
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG exists — uploading assets (clobber)."
else
  echo "Creating release $TAG."
  gh release create "$TAG" --repo "$REPO" \
    --title "KDWarm runtime binaries ($TAG)" \
    --notes "Self-built, relocatable macOS arm64 runtime/engine artifacts (PHP, Redis, Postgres) for KDWarm's on-demand installer. Each .tar.gz has a matching .sha256." \
    --latest=false
fi

gh release upload "$TAG" --repo "$REPO" --clobber "${UPLOADS[@]}"
echo "=== Done. Assets at https://github.com/$REPO/releases/tag/$TAG ==="
