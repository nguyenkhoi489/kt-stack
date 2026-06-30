#!/usr/bin/env bash
# Build a relocatable Apache httpd from the Homebrew bottle and produce an on-demand artifact
# (tar.gz + sha256). Apache is a per-site web-server engine installed on demand (never bundled in
# the .app), so this does NOT copy into Resources/bin — it stages a self-contained apache-<ver>/
# tree (bin/httpd + modules/*.so + lib/ closure + conf/mime.types) for a release host.
#
# httpd loads mod_*.so at runtime and links libapr-1/libaprutil-1/libpcre2; that deep closure is the
# PHP recursive-relocate case (vendor_nonsystem_dylibs_recursive), NOT the 2-level nginx path.
# Relocation is proven by re-running `httpd -v` and a config syntax test from a MOVED copy with no
# Homebrew on PATH.
#
# arm64 builds natively; x86_64 builds via `arch -x86_64 /usr/local/bin/brew` (no Intel hardware).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

ARCH="${ARCH:-$(uname -m)}"
ARTIFACTS="${ARTIFACTS:-$ROOT/.build-cache/artifacts}"
STAGE_ROOT="${STAGE_ROOT:-$ROOT/.build-cache/apache-$ARCH}"
source "$ROOT/scripts/lib-relocatable.sh"
BREW="$(brew_for_arch)"

# Modules KTStack's per-site backend needs: mod_proxy_fcgi → PHP-FPM, rewrite/headers for .htaccess
# parity, plus the minimum to boot httpd standalone. Keep in sync with ApacheBackend.loadModules.
MODULES=(
    mod_mpm_event mod_authz_core mod_unixd mod_log_config mod_mime mod_dir
    mod_env mod_setenvif mod_headers mod_rewrite mod_proxy mod_proxy_fcgi
)

echo "=== Apache build (${ARCH}) from Homebrew bottle ==="
mkdir -p "$ARTIFACTS"

if ! $BREW list --formula 2>/dev/null | grep -qx "httpd"; then
    echo "=== brew install httpd ==="
    $BREW install httpd
fi

CELLAR="$($BREW --prefix httpd)"
VER="$($BREW list --versions httpd | awk '{print $2}' | head -1)"
[[ -x "$CELLAR/bin/httpd" ]] || { echo "httpd binary missing in $CELLAR/bin" >&2; exit 1; }
MOD_SRC="$CELLAR/lib/httpd/modules"
echo "  cellar: $CELLAR   version: $VER"

TOP="$STAGE_ROOT/apache-$VER"
rm -rf "$TOP"
mkdir -p "$TOP/bin" "$TOP/modules" "$TOP/lib" "$TOP/conf" "$TOP/logs"

cp "$CELLAR/bin/httpd" "$TOP/bin/httpd"; chmod u+w "$TOP/bin/httpd"

MIME_SRC=""
for cand in "$CELLAR/.bottle/etc/httpd/mime.types" "$($BREW --prefix)/etc/httpd/mime.types"; do
    [[ -f "$cand" ]] && { MIME_SRC="$cand"; break; }
done
[[ -n "$MIME_SRC" ]] || { echo "mime.types not found" >&2; exit 1; }
cp "$MIME_SRC" "$TOP/conf/mime.types"

WORK=("$TOP/bin/httpd::$CELLAR/bin")
for m in "${MODULES[@]}"; do
    [[ -f "$MOD_SRC/$m.so" ]] || { echo "  ✗ required module $m.so missing" >&2; exit 1; }
    cp "$MOD_SRC/$m.so" "$TOP/modules/$m.so"; chmod u+w "$TOP/modules/$m.so"
    WORK+=("$TOP/modules/$m.so::$MOD_SRC")
done

echo "  -- vendor transitive closure (apr, apr-util, pcre2, …) --"
vendor_nonsystem_dylibs_recursive "$TOP" "${WORK[@]}"
VENDORED="$(ls "$TOP/lib" 2>/dev/null | wc -l | tr -d ' ')"
echo "  vendored: $VENDORED dylibs"

echo "  -- deep gate --"
gate_fail=0
for f in "$TOP/bin/httpd" "$TOP"/modules/*.so "$TOP"/lib/*.dylib; do
    [[ -e "$f" ]] || continue
    relocatable_gate_deep "$f" "$TOP" >/dev/null || { relocatable_gate_deep "$f" "$TOP" || true; gate_fail=1; }
done
((gate_fail)) && { echo "  ✗ GATE FAILED" >&2; exit 1; }
echo "  ✓ gate clean"

for f in "$TOP/bin/httpd" "$TOP"/modules/*.so "$TOP"/lib/*.dylib; do
    [[ -e "$f" ]] || continue
    ad_hoc_sign "$f" >/dev/null 2>&1
done

echo "=== PROVE relocation: httpd -v + config test from a MOVED copy, no Homebrew on PATH ==="
RELOC="$(mktemp -d)/moved"; mkdir -p "$RELOC"; cp -R "$TOP" "$RELOC/"
MDIR="$RELOC/apache-$VER"
TESTCONF="$MDIR/conf/test.conf"
{
    echo "ServerRoot \"$MDIR\""
    echo "Listen 127.0.0.1:18080"
    for m in "${MODULES[@]}"; do
        modname="${m#mod_}_module"
        echo "LoadModule $modname modules/$m.so"
    done
    echo "TypesConfig \"$MDIR/conf/mime.types\""
    echo "ServerName localhost"
    echo "PidFile \"$MDIR/logs/httpd.pid\""
    echo "ErrorLog \"$MDIR/logs/error.log\""
} > "$TESTCONF"
env -i PATH=/usr/bin:/bin "$MDIR/bin/httpd" -v >/tmp/apache-reloc.log 2>&1 \
    && env -i PATH=/usr/bin:/bin "$MDIR/bin/httpd" -d "$MDIR" -f "$TESTCONF" -t >>/tmp/apache-reloc.log 2>&1 \
    && echo "  ✓ httpd runs and loads all modules from moved path" \
    || { echo "  ✗ httpd failed from moved path:"; tail -12 /tmp/apache-reloc.log; exit 1; }
rm -rf "$RELOC"

package_dir "$TOP" "$ARTIFACTS"
echo "APACHE BUILD OK ($VER, $ARCH, $VENDORED dylibs)"
