#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

DEFAULT_VERSIONS=(7.4 8.0 8.1 8.2 8.3 8.4)
if [[ $# -gt 0 ]]; then
    VERSIONS=("$@")
elif [[ -n "${PHP_VERSIONS:-}" ]]; then
    read -r -a VERSIONS <<< "$PHP_VERSIONS"
else
    VERSIONS=("${DEFAULT_VERSIONS[@]}")
fi

ARCH="${ARCH:-$(uname -m)}"
ARTIFACTS="${ARTIFACTS:-$ROOT/.build-cache/artifacts}"
STAGE_ROOT="${STAGE_ROOT:-$ROOT/.build-cache/php-from-brew-$ARCH}"
LOCKFILE="${LOCKFILE:-$ROOT/scripts/php-bottle-pins.lock}"
UPDATE_LOCK="${UPDATE_LOCK:-0}"

# shellcheck source=scripts/lib-relocatable.sh
source "$ROOT/scripts/lib-relocatable.sh"

mkdir -p "$ARTIFACTS"

bottle_tag() {
    local macos_major
    macos_major="$(sw_vers -productVersion | cut -d. -f1)"
    case "$macos_major" in
        15) echo "arm64_sequoia" ;;
        14) echo "arm64_sonoma" ;;
        13) echo "arm64_ventura" ;;
        *)  echo "arm64_sequoia" ;;
    esac
}

cellar_version_of() {
    brew info --json=v2 "shivammathur/php/php@$1" 2>/dev/null \
        | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["formulae"][0]["versions"]["stable"])'
}

bottle_sha_of() {
    local ver="$1" tag="$2"
    brew info --json=v2 "shivammathur/php/php@$ver" 2>/dev/null \
        | /usr/bin/python3 -c "import json,sys; f=json.load(sys.stdin)['formulae'][0]; b=f.get('bottle',{}).get('stable',{}).get('files',{}); print(b.get('$tag',{}).get('sha256',''))"
}

pinned_field() {
    local ver="$1" col="$2"
    [[ -f "$LOCKFILE" ]] || { echo ""; return; }
    awk -v v="$ver" -F'\t' '$1==v {print $('"$col"')}' "$LOCKFILE"
}

update_lock_entry() {
    local ver="$1" cv="$2" bs="$3" tmp
    tmp="$(mktemp)"
    { [[ -f "$LOCKFILE" ]] && awk -F'\t' -v v="$ver" '!/^#/ && $1!=v' "$LOCKFILE" 2>/dev/null || true; } > "$tmp"
    printf '%s\t%s\t%s\n' "$ver" "$cv" "$bs" >> "$tmp"
    sort -o "$tmp" "$tmp"
    { echo "# php-bottle-pins.lock — version<TAB>cellar_version<TAB>bottle_sha256 ($(bottle_tag))"; cat "$tmp"; } > "$LOCKFILE"
    rm -f "$tmp"
}

build_one_version() {
    local PHP_VERSION="$1"
    local FORMULA="shivammathur/php/php@${PHP_VERSION}"
    local TAG; TAG="$(bottle_tag)"
    echo ""
    echo "######## PHP ${PHP_VERSION} (${ARCH}, ${TAG}) ########"

    if ! brew list --formula 2>/dev/null | grep -qx "php@${PHP_VERSION}"; then
        echo "=== brew install ${FORMULA} ==="
        if ! brew install "$FORMULA"; then
            echo "=== bottle unavailable — build from source ==="
            brew install --build-from-source "$FORMULA"
        fi
    fi

    local CV BS
    CV="$(cellar_version_of "$PHP_VERSION")"
    BS="$(bottle_sha_of "$PHP_VERSION" "$TAG")"
    echo "  cellar version: $CV   bottle sha: ${BS:0:12}…"

    if [[ "$UPDATE_LOCK" == "1" ]]; then
        update_lock_entry "$PHP_VERSION" "$CV" "$BS"
        echo "  lock updated."
    else
        local PIN_CV; PIN_CV="$(pinned_field "$PHP_VERSION" 2)"
        if [[ -n "$PIN_CV" && "$PIN_CV" != "$CV" ]]; then
            echo "  ✗ pin drift: installed $CV != pinned $PIN_CV (run UPDATE_LOCK=1 to repin)" >&2
            return 1
        fi
        [[ -z "$PIN_CV" ]] && echo "  ! no pin recorded for $PHP_VERSION (run UPDATE_LOCK=1 to record)"
    fi

    local CELLAR; CELLAR="$(brew --prefix "php@${PHP_VERSION}")"
    [[ -x "$CELLAR/bin/php" ]] || { echo "php binary missing in $CELLAR" >&2; return 1; }

    local FPM_SRC=""
    for cand in "$CELLAR/sbin/php-fpm" "$CELLAR/bin/php-fpm"; do
        [[ -x "$cand" ]] && { FPM_SRC="$cand"; break; }
    done
    [[ -n "$FPM_SRC" ]] || { echo "php-fpm not found under $CELLAR/{sbin,bin}" >&2; return 1; }

    local API SO_DIR
    API="$("$CELLAR/bin/php" -i | awk -F'=> ' '/^PHP API/{gsub(/ /,"",$2); print $2}')"
    SO_DIR="$CELLAR/lib/php/$API"
    echo "  php-fpm: $FPM_SRC   API: $API"

    local TOP="$STAGE_ROOT/php-${PHP_VERSION}"
    rm -rf "$TOP"
    mkdir -p "$TOP/bin" "$TOP/lib" "$TOP/modules" "$TOP/conf.d"

    cp "$CELLAR/bin/php" "$TOP/bin/php"
    cp "$FPM_SRC" "$TOP/bin/php-fpm"
    chmod u+w "$TOP/bin/php" "$TOP/bin/php-fpm"

    local -a WORK=("$TOP/bin/php::$CELLAR/bin" "$TOP/bin/php-fpm::$(dirname "$FPM_SRC")")
    if [[ -d "$SO_DIR" ]]; then
        local so b
        for so in "$SO_DIR"/*.so; do
            [[ -e "$so" ]] || continue
            b="$(basename "$so")"
            cp "$so" "$TOP/modules/$b"; chmod u+w "$TOP/modules/$b"
            WORK+=("$TOP/modules/$b::$SO_DIR")
        done
    fi

    echo "  -- vendor transitive closure --"
    vendor_nonsystem_dylibs_recursive "$TOP" "${WORK[@]}"
    local VENDORED; VENDORED="$(ls "$TOP/lib" 2>/dev/null | wc -l | tr -d ' ')"
    echo "  vendored: $VENDORED dylibs"

    echo "  -- deep gate --"
    local m gate_fail=0
    for m in "$TOP/bin/php" "$TOP/bin/php-fpm" "$TOP"/modules/*.so "$TOP"/lib/*.dylib; do
        [[ -e "$m" ]] || continue
        relocatable_gate_deep "$m" "$TOP" >/dev/null || { relocatable_gate_deep "$m" "$TOP" || true; gate_fail=1; }
    done
    ((gate_fail)) && { echo "  ✗ GATE FAILED ($PHP_VERSION)" >&2; return 1; }
    echo "  ✓ gate clean"

    for m in "$TOP/bin/php" "$TOP/bin/php-fpm" "$TOP"/modules/*.so "$TOP"/lib/*.dylib; do
        [[ -e "$m" ]] || continue
        ad_hoc_sign "$m" >/dev/null 2>&1
    done

    package_dir "$TOP" "$ARTIFACTS"
    echo "  ✓ PHP $PHP_VERSION OK ($VENDORED dylibs)"
}

echo "=== php-from-brew matrix: ${VERSIONS[*]} ==="
FAILED=()
for v in "${VERSIONS[@]}"; do
    build_one_version "$v" || FAILED+=("$v")
done

echo ""
echo "=== sha256 summary (provisional dev — Developer-ID sign in Phase 3 changes these) ==="
for v in "${VERSIONS[@]}"; do
    f="$ARTIFACTS/php-${v}-${ARCH}.tar.gz"
    [[ -f "$f.sha256" ]] && printf '  %s  %s\n' "$v" "$(awk '{print $1}' "$f.sha256")"
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "" >&2; echo "✗ FAILED versions: ${FAILED[*]}" >&2; exit 1
fi
echo ""
echo "ALL PHP BUILDS OK: ${VERSIONS[*]}"
