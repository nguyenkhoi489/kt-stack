#!/usr/bin/env bash
# Developer-ID-sign a KDWarm.app inside-out (children before parents) with Hardened Runtime and the
# correct per-binary entitlements. `--deep` is deliberately NOT used (it mis-signs nested code); we
# enumerate every Mach-O and sign deepest-first, then frameworks, the helper, and the app last.
#
# Usage: DEV_ID="Developer ID Application: NAME (TEAMID)" scripts/release/sign-all-binaries.sh KDWarm.app
# Requires: a Developer ID Application identity in the login keychain.
#
# SCOPE: this signs the BUNDLED binaries (Resources/bin: nginx, the bundled PHP 8.4 php/php-fpm,
# dnsmasq, mkcert, Mailpit). The ON-DEMAND artifacts (extra PHP versions, Node, Go, Python, DB
# engines downloaded post-install into ~/Library/Application Support) are NOT reachable here — they
# must be Developer-ID-signed with the SAME entitlements at PUBLISH time inside their build scripts
# (JIT runtimes → jit-runtime.entitlements) and notarized, so they run under Hardened Runtime when
# downloaded. The on-demand download path verifies their checksum before use.
set -euo pipefail
APP="${1:?usage: sign-all-binaries.sh <path-to-.app>}"
DEV_ID="${DEV_ID:?set DEV_ID to your 'Developer ID Application: …' identity}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENT="$ROOT/entitlements"
BASE_ENT="$ENT/app.entitlements"
JIT_ENT="$ENT/jit-runtime.entitlements"

sign() { # <entitlements> <path>
    codesign --force --options runtime --timestamp --sign "$DEV_ID" --entitlements "$1" "$2"
}

sign_lib() { # <path> — shared libraries carry no app entitlements
    codesign --force --options runtime --timestamp --sign "$DEV_ID" "$1"
}

# JIT runtimes (PHP-with-opcache.jit, Node/V8, Java, Ruby) need allow-jit; everything else base.
needs_jit() {
    case "$(basename "$1")" in
        php|php-fpm|php-*|node|java|ruby) return 0 ;;
        *) return 1 ;;
    esac
}

is_macho() { file -b "$1" | grep -q "Mach-O"; }
is_library() { case "$(basename "$1")" in *.dylib|*.so) return 0 ;; *) return 1 ;; esac; }

sign_by_kind() { # <path> — JIT → jit ent, library → no ent, else → base ent
    local b; b="$(basename "$1")"
    if needs_jit "$1"; then echo "  jit  $b"; sign "$JIT_ENT" "$1"
    elif is_library "$1"; then echo "  lib  $b"; sign_lib "$1"
    else echo "  exe  $b"; sign "$BASE_ENT" "$1"; fi
}

echo "=== 1. bundled binaries (Resources/bin) — deepest first ==="
if [[ -d "$APP/Contents/Resources/bin" ]]; then
    while IFS= read -r -d '' f; do
        is_macho "$f" || continue
        if needs_jit "$f"; then echo "  jit  $(basename "$f")"; sign "$JIT_ENT" "$f"
        else echo "  base $(basename "$f")"; sign "$BASE_ENT" "$f"; fi
    done < <(find "$APP/Contents/Resources/bin" -type f -print0)
fi

echo "=== 2. embedded frameworks (KDWarmKit, Sparkle + its nested code) ==="
if [[ -d "$APP/Contents/Frameworks" ]]; then
    # Sparkle ships signable nested code as siblings under Versions/B (XPCServices/*.xpc, the loose
    # Autoupdate helper tool, Updater.app) — sign each explicitly BEFORE sealing the .framework. The
    # generic loose-Mach-O sweep below can leave the Autoupdate helper ad-hoc, which notarization
    # rejects with "not signed with a valid Developer ID certificate / no secure timestamp".
    SP="$APP/Contents/Frameworks/Sparkle.framework"
    if [[ -d "$SP" ]]; then
        while IFS= read -r -d '' xpc; do echo "  xpc  $(basename "$xpc")"; sign "$BASE_ENT" "$xpc"; done \
            < <(find "$SP" -name "*.xpc" -type d -print0)
        while IFS= read -r -d '' au; do echo "  exe  $(basename "$au")"; sign "$BASE_ENT" "$au"; done \
            < <(find "$SP" -name "Autoupdate" -type f -print0)
        while IFS= read -r -d '' app; do echo "  app  $(basename "$app")"; sign "$BASE_ENT" "$app"; done \
            < <(find "$SP" -name "*.app" -type d -print0)
    fi
    # Any other loose Mach-O / dylibs not inside an already-sealed nested bundle (xpc/app/framework).
    # Match the path RELATIVE to Frameworks: the outer bundle is itself "<name>.app", so an absolute
    # path matches *.app/* and would skip every file.
    while IFS= read -r -d '' f; do
        rel="${f#"$APP/Contents/Frameworks/"}"
        case "$rel" in *.xpc/*|*.app/*|*.framework/*) continue ;; esac
        is_macho "$f" && sign_by_kind "$f"
    done < <(find "$APP/Contents/Frameworks" -type f \( -perm -111 -o -name "*.dylib" \) -print0)
    # Finally seal each framework bundle itself.
    for fw in "$APP"/Contents/Frameworks/*.framework; do
        [[ -d "$fw" ]] && { echo "  fw   $(basename "$fw")"; sign "$BASE_ENT" "$fw"; }
    done
fi

echo "=== 3. privileged helper ==="
HELPER="$APP/Contents/MacOS/KDWarmHelper"
[[ -f "$HELPER" ]] && sign "$ENT/helper.entitlements" "$HELPER"

echo "=== 4. the app bundle (last) ==="
sign "$BASE_ENT" "$APP"

# Final guard: no nested Mach-O may reach notarization ad-hoc or without a secure timestamp (Xcode's
# "Sign to Run Locally" can re-adhoc-sign Swift runtime dylibs after a Release build). Re-sign any
# offender with the correct entitlements, re-seal the app, then hard-fail if any remain.
needs_resign() { # <path> — true if ad-hoc signed or lacking a secure timestamp
    local d; d="$(codesign -dvv "$1" 2>&1)" || return 0
    grep -q "Signature=adhoc" <<<"$d" && return 0
    grep -q "^Timestamp=" <<<"$d" || return 0
    return 1
}

echo "=== 5. guard: every nested Mach-O Developer-ID-signed with a secure timestamp ==="
resigned=0
while IFS= read -r -d '' f; do
    is_macho "$f" || continue
    needs_resign "$f" || continue
    echo "  fix  ${f#"$APP/"}"; sign_by_kind "$f"; resigned=1
done < <(find "$APP" -type f -print0)
if [[ "$resigned" == 1 ]]; then echo "  re-seal app after late re-sign"; sign "$BASE_ENT" "$APP"; fi

offenders=()
while IFS= read -r -d '' f; do
    is_macho "$f" || continue
    needs_resign "$f" && offenders+=("${f#"$APP/"}")
done < <(find "$APP" -type f -print0)
if (( ${#offenders[@]} )); then
    echo "FATAL: nested binaries still ad-hoc / missing secure timestamp:" >&2
    printf '  %s\n' "${offenders[@]}" >&2
    exit 1
fi

echo "=== verify ==="
codesign --verify --deep --strict --verbose=2 "$APP"
echo "SIGN OK — run scripts/release/notarize.sh next"
