#!/usr/bin/env bash
# Shared helpers for the relocatable build scripts: the otool relocatability gate, ad-hoc signing,
# and packaging a runtime into the on-demand artifact format (a single top-level <name>-<version>/
# dir → tar.gz + .sha256, matching RuntimeDownloader's "single top-level dir" extract assumption).
# Source this from a build script: `source "$ROOT/scripts/lib-relocatable.sh"`.

# Fail unless every linked dylib is a system lib or a relative (@rpath/@executable_path/@loader_path)
# reference — i.e. no Homebrew/Cellar absolute paths that would break when the binary is relocated.
relocatable_gate() {
    local bin="$1"
    otool -L "$bin"
    local bad
    bad=$(otool -L "$bin" | tail -n +2 | awk '{print $1}' \
            | grep -vE '^(/usr/lib/|/System/|@rpath/|@executable_path/|@loader_path/)' || true)
    if [[ -n "$bad" ]]; then
        echo "  ✗ leaked dylib refs in $(basename "$bin"):" >&2
        echo "$bad" | sed 's/^/    /' >&2
        return 1
    fi
    echo "  ✓ $(basename "$bin") relocatable"
}

# Ad-hoc codesign so BinaryStager / the downloader's `codesign --verify` passes in dev and the cdhash
# seals the binary against post-stage tampering. Phase 9 replaces this with a Developer ID signature.
ad_hoc_sign() { codesign --force --sign - "$@"; }

sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

# Tar a prepared top-level dir into the artifacts dir + write its sha256. $1 = top dir
# (named "<name>-<version>" with content under it, e.g. bin/…), $2 = artifacts dir.
package_dir() {
    local top="$1" artifacts="$2"
    local name arch out sha
    name="$(basename "$top")"
    arch="$(uname -m)"
    mkdir -p "$artifacts"
    out="$artifacts/${name}-${arch}.tar.gz"
    tar -czf "$out" -C "$(dirname "$top")" "$name"
    sha="$(sha256_of "$out")"
    echo "$sha  $(basename "$out")" > "$out.sha256"
    echo "  artifact: $out"
    echo "  sha256:   $sha"
}

# Package one optional shared extension as the install/uninstall artifact:
#   php-ext-<ext>-<phpver>-<arch>.tar.gz  with a single top-level <ext>/ dir holding <ext>.so.
# The single-top-level-dir shape matches RuntimeDownloader's extract assumption (the dir name is
# stripped on extract; the catalog keys off the inner <ext>.so name). Distinct from package_dir,
# which derives the artifact name FROM the top dir — here the top dir is the bare <ext>.
# $1=.so path  $2=ext name  $3=php minor (e.g. 8.4)  $4=artifacts dir.
package_extension() {
    local so="$1" ext="$2" phpver="$3" artifacts="$4"
    local arch stage top out sha
    arch="$(uname -m)"
    mkdir -p "$artifacts"
    stage="$(mktemp -d)"; top="$stage/$ext"; mkdir -p "$top"
    cp "$so" "$top/$ext.so"
    out="$artifacts/php-ext-${ext}-${phpver}-${arch}.tar.gz"
    tar -czf "$out" -C "$stage" "$ext"
    sha="$(sha256_of "$out")"
    echo "$sha  $(basename "$out")" > "$out.sha256"
    rm -rf "$stage"
    echo "  artifact: $out"
    echo "  sha256:   $sha"
}

# Vendor a binary's non-system dylib dependencies (e.g. Homebrew openssl) INTO <libdir> and rewrite
# the references to @loader_path/../lib so the result is relocatable. Bounded to two levels (the
# binary's deps + those deps' own non-system deps), which covers the openssl→nothing case. $1=binary
# (in .../bin), $2=libdir (sibling .../lib). Adds an rpath to the binary.
vendor_nonsystem_dylibs() {
    local bin="$1" libdir="$2"
    mkdir -p "$libdir"
    _vendor_one "$bin" "$libdir"
    install_name_tool -add_rpath "@loader_path/../lib" "$bin" 2>/dev/null || true
    # Second pass: fix references inside the vendored dylibs themselves.
    local d
    for d in "$libdir"/*.dylib; do [[ -e "$d" ]] && _vendor_one "$d" "$libdir"; done
}
_vendor_one() {
    local obj="$1" libdir="$2" ref base
    while read -r ref; do
        case "$ref" in
            /usr/lib/*|/System/*|@*) continue ;;       # system or already-relative
        esac
        base="$(basename "$ref")"
        [[ -f "$libdir/$base" ]] || cp "$ref" "$libdir/$base" 2>/dev/null || continue
        install_name_tool -id "@loader_path/../lib/$base" "$libdir/$base" 2>/dev/null || true
        install_name_tool -change "$ref" "@loader_path/../lib/$base" "$obj" 2>/dev/null || true
    done < <(otool -L "$obj" | tail -n +2 | awk '{print $1}')
}

# Convenience for single-binary runtimes: stage one binary at <relpath> inside a fresh
# "<name>-<version>" dir, then package. $1=binary $2=name $3=version $4=relpath $5=artifacts-dir.
package_artifact() {
    local bin="$1" name="$2" version="$3" relpath="$4" artifacts="$5"
    local stage top
    stage="$(mktemp -d)"
    top="$stage/${name}-${version}"
    mkdir -p "$top/$(dirname "$relpath")"
    cp "$bin" "$top/$relpath"
    package_dir "$top" "$artifacts"
    rm -rf "$stage"
}
