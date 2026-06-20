#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"

DEFAULT_VERSIONS=(7.4 8.0 8.1 8.2 8.3 8.4)
if [[ $# -gt 0 ]]; then VERSIONS=("$@"); else VERSIONS=("${DEFAULT_VERSIONS[@]}"); fi

ARCH="${ARCH:-$(uname -m)}"
ARTIFACTS="${ARTIFACTS:-$ROOT/.build-cache/artifacts}"
RUNTIME_STAGE="${RUNTIME_STAGE:-$ROOT/.build-cache/php-from-brew-$ARCH}"
EXT_BUILD="${EXT_BUILD:-$ROOT/.build-cache/php-ext-$ARCH}"

EXT_DEFAULT="redis apcu xdebug xhprof mongodb protobuf swoole xlswriter zstd imagick memcached ssh2 event"
read -r -a EXT_LIST <<< "${EXTENSIONS:-$EXT_DEFAULT}"

source "$ROOT/scripts/lib-relocatable.sh"
mkdir -p "$ARTIFACTS" "$EXT_BUILD"

brew_prefix() { brew --prefix "$1" 2>/dev/null; }
ensure_dep() { brew list --formula 2>/dev/null | grep -qx "$1" || brew install "$1" >/dev/null 2>&1; }

ensure_dep pkgconf
export PKG_CONFIG_PATH="$(brew_prefix openssl@3)/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

ext_source_url() {
    case "$1" in
        zstd) echo "git:https://github.com/kjdev/php-ext-zstd.git" ;;
        snmp) echo "phpsrc:snmp" ;;
        *)    echo "pecl:$1" ;;
    esac
}

cellar_full_version() {
    awk -F'\t' -v v="$1" '!/^#/ && $1==v {print $2}' "$ROOT/scripts/php-bottle-pins.lock" 2>/dev/null
}

ext_configure_args() {
    local ext="$1"
    case "$ext" in
        imagick)   ensure_dep imagemagick; echo "--with-imagick=$(brew_prefix imagemagick)" ;;
        memcached) ensure_dep libmemcached; ensure_dep zlib
                   echo "--with-libmemcached-dir=$(brew_prefix libmemcached) --with-zlib-dir=$(brew_prefix zlib) --disable-memcached-sasl" ;;
        ssh2)      ensure_dep libssh2; echo "--with-ssh2=$(brew_prefix libssh2)" ;;
        event)     ensure_dep libevent; ensure_dep openssl@3
                   echo "--with-event-core --with-event-extra --with-event-libevent-dir=$(brew_prefix libevent) --with-event-openssl-dir=$(brew_prefix openssl@3)" ;;
        zstd)      ensure_dep zstd; echo "--with-libzstd" ;;
        snmp)      ensure_dep net-snmp; echo "--with-snmp=$(brew_prefix net-snmp)" ;;
        grpc)      echo "--enable-grpc" ;;
        *)         echo "" ;;
    esac
}

ext_load_directive() { case "$1" in xdebug) echo zend_extension ;; *) echo extension ;; esac; }

fetch_source() {
    local ext="$1" dest="$2" ver="$3" spec scheme val cfg full
    spec="$(ext_source_url "$ext")"; scheme="${spec%%:*}"; val="${spec#*:}"
    rm -rf "$dest"; mkdir -p "$dest"
    case "$scheme" in
        pecl)
            curl -fsSL "https://pecl.php.net/get/$val" -o "$dest/src.tgz" || return 1
            tar -xf "$dest/src.tgz" -C "$dest" || return 1
            cfg="$(find "$dest" -name config.m4 -not -path '*/tests/*' | head -1)" ;;
        git)
            git clone --depth 1 "$val" "$dest/src" >/dev/null 2>&1 || return 1
            cfg="$(find "$dest" -name config.m4 -not -path '*/tests/*' | head -1)" ;;
        phpsrc)
            full="$(cellar_full_version "$ver")"
            [[ -n "$full" ]] || return 1
            curl -fsSL "https://www.php.net/distributions/php-${full}.tar.gz" -o "$dest/php.tgz" \
                || curl -fsSL "https://museum.php.net/php8/php-${full}.tar.gz" -o "$dest/php.tgz" \
                || curl -fsSL "https://museum.php.net/php7/php-${full}.tar.gz" -o "$dest/php.tgz" || return 1
            tar -xf "$dest/php.tgz" -C "$dest" || return 1
            cfg="$(find "$dest/php-${full}/ext/$val" -name config.m4 | head -1)" ;;
    esac
    [[ -n "$cfg" ]] && dirname "$cfg"
}

gate_extension_so() {
    local stage="$1" runtime_lib="$2" m ref bad=0 base
    for m in "$stage"/*.so "$stage"/*.dylib; do
        [[ -e "$m" ]] || continue
        while IFS= read -r ref; do
            case "$ref" in
                /usr/lib/*|/System/*) continue ;;
                @loader_path/../lib/*)
                    base="${ref##*/}"
                    [[ -f "$runtime_lib/$base" ]] || { echo "  ✗ $(basename "$m"): runtime lib missing $base" >&2; bad=1; } ;;
                @loader_path/*)
                    base="${ref#@loader_path/}"
                    [[ -f "$stage/$base" ]] || { echo "  ✗ $(basename "$m"): sidecar missing $base" >&2; bad=1; } ;;
                *) echo "  ✗ $(basename "$m"): non-relocatable ref $ref" >&2; bad=1 ;;
            esac
        done < <(otool -L "$m" | tail -n +2 | awk '{print $1}')
    done
    return $bad
}

build_one() {
    local ext="$1" ver="$2"
    local CELLAR; CELLAR="$(brew --prefix "php@${ver}" 2>/dev/null)"
    [[ -x "$CELLAR/bin/phpize" ]] || { echo "  ✗ php@$ver not installed"; return 1; }
    local runtime_lib="$RUNTIME_STAGE/php-${ver}/lib"
    [[ -d "$runtime_lib" ]] || { echo "  ✗ runtime lib missing for $ver (build base first)"; return 1; }

    local work="$EXT_BUILD/$ver/$ext"
    local srcdir; srcdir="$(fetch_source "$ext" "$work" "$ver")" || { echo "  ✗ fetch $ext failed"; return 1; }
    [[ -n "$srcdir" && -d "$srcdir" ]] || { echo "  ✗ no source dir for $ext"; return 1; }

    local pcre2_inc; pcre2_inc="$(brew_prefix pcre2)/include"
    local ssl_inc; ssl_inc="$(brew_prefix openssl@3)/include"
    ( cd "$srcdir"
      export CPPFLAGS="-I${pcre2_inc} -I${ssl_inc} ${CPPFLAGS:-}"
      export LDFLAGS="-L$(brew_prefix openssl@3)/lib ${LDFLAGS:-}"
      "$CELLAR/bin/phpize" >/dev/null 2>&1 || exit 1
      # shellcheck disable=SC2046
      ./configure --with-php-config="$CELLAR/bin/php-config" $(ext_configure_args "$ext") >/dev/null 2>&1 || exit 1
      make -j"$(sysctl -n hw.ncpu)" >/dev/null 2>&1 || exit 1
    ) || { echo "  ✗ build $ext@$ver failed"; return 1; }

    local so; so="$(find "$srcdir/modules" -name "${ext}.so" 2>/dev/null | head -1)"
    [[ -f "$so" ]] || so="$(find "$srcdir/modules" -name '*.so' 2>/dev/null | head -1)"
    [[ -f "$so" ]] || { echo "  ✗ no .so produced for $ext@$ver"; return 1; }

    local stage="$work/stage"; rm -rf "$stage"; mkdir -p "$stage"
    cp "$so" "$stage/${ext}.so"; chmod u+w "$stage/${ext}.so"
    vendor_extension_so "$stage/${ext}.so" "$runtime_lib"

    local m
    for m in "$stage"/*.so "$stage"/*.dylib; do [[ -e "$m" ]] && ad_hoc_sign "$m" >/dev/null 2>&1; done

    gate_extension_so "$stage" "$runtime_lib" || { echo "  ✗ $ext@$ver failed relocate gate"; return 1; }

    local rt="$RUNTIME_STAGE/php-${ver}"
    local php="$rt/bin/php" mod="$rt/modules"
    local directive; directive="$(ext_load_directive "$ext")"
    local f probe_files=()
    for f in "$stage"/*.so "$stage"/*.dylib; do
        [[ -e "$f" ]] || continue
        cp "$f" "$mod/$(basename "$f")"; probe_files+=("$mod/$(basename "$f")")
    done
    local loadarg
    if [[ "$directive" == zend_extension ]]; then loadarg="-d zend_extension=$mod/${ext}.so"
    else loadarg="-d extension=${ext}.so"; fi
    local load_ok=1
    env -i "$php" -d extension_dir="$mod" $loadarg -r 'exit(0);' >/dev/null 2>&1 || load_ok=0
    for f in "${probe_files[@]}"; do rm -f "$f"; done
    if ((!load_ok)); then
        echo "  ✗ $ext@$ver did not load under env -i (fail-closed; not published)"; return 1
    fi

    package_extension "$stage/${ext}.so" "$ext" "$ver" "$ARTIFACTS" >/dev/null
    local sidecars; sidecars="$(ls "$stage"/*.dylib 2>/dev/null | wc -l | tr -d ' ')"
    local sha; sha="$(sha256_of "$ARTIFACTS/php-ext-${ext}-${ver}-${ARCH}.tar.gz")"
    echo "  ✓ $ext@$ver ($sidecars sidecar dylibs)  sha:${sha:0:12}…"
    echo "$ext	$ver	$sha" >> "$ARTIFACTS/php-ext-built.tsv"
    return 0
}

: > "$ARTIFACTS/php-ext-built.tsv"
FAILED=()
for ver in "${VERSIONS[@]}"; do
    echo ""
    echo "######## ext matrix — PHP $ver ########"
    for ext in "${EXT_LIST[@]}"; do
        build_one "$ext" "$ver" || FAILED+=("$ext@$ver")
    done
done

echo ""
echo "=== built extensions (ext ver sha) ==="
cat "$ARTIFACTS/php-ext-built.tsv" 2>/dev/null
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""; echo "✗ FAILED (${#FAILED[@]}): ${FAILED[*]}"
fi
echo ""
echo "ext matrix done: $(wc -l < "$ARTIFACTS/php-ext-built.tsv" 2>/dev/null) built, ${#FAILED[@]} failed"
