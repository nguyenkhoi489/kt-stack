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

brew_for_arch() {
    local a="${ARCH:-$(uname -m)}"
    if [[ "$a" == "x86_64" && "$(uname -m)" == "arm64" ]]; then
        echo "arch -x86_64 /usr/local/bin/brew"
    elif [[ "$a" == "x86_64" ]]; then
        echo "/usr/local/bin/brew"
    else
        echo "brew"
    fi
}

# Tar a prepared top-level dir into the artifacts dir + write its sha256. $1 = top dir
# (named "<name>-<version>" with content under it, e.g. bin/…), $2 = artifacts dir.
package_dir() {
    local top="$1" artifacts="$2"
    local name arch out sha
    name="$(basename "$top")"
    arch="${ARCH:-$(uname -m)}"
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
    arch="${ARCH:-$(uname -m)}"
    mkdir -p "$artifacts"
    stage="$(mktemp -d)"; top="$stage/$ext"; mkdir -p "$top"
    cp "$so" "$top/$ext.so"
    local sidecar
    for sidecar in "$(dirname "$so")"/*.dylib; do
        [[ -e "$sidecar" ]] && cp "$sidecar" "$top/$(basename "$sidecar")"
    done
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

_canonicalize() { /usr/bin/perl -MCwd -e 'my $p = Cwd::abs_path($ARGV[0]); print $p if defined $p' "$1"; }

_is_system_path() {
    case "$1" in
        /usr/lib/*|/System/*) return 0 ;;
        *) return 1 ;;
    esac
}

_macho_rpaths() {
    otool -l "$1" | awk '
        $2 == "LC_RPATH" { inrpath = 1; next }
        inrpath && $1 == "path" { print $2; inrpath = 0 }'
}

_resolve_ref() {
    local ref="$1" loader_dir="$2" obj="$3" candidate resolved rp rp_resolved
    case "$ref" in
        @loader_path/*) candidate="${loader_dir}/${ref#@loader_path/}" ;;
        @executable_path/*) candidate="${loader_dir}/${ref#@executable_path/}" ;;
        @rpath/*)
            while IFS= read -r rp; do
                [[ -z "$rp" ]] && continue
                case "$rp" in
                    @loader_path/*) rp_resolved="${loader_dir}/${rp#@loader_path/}" ;;
                    @executable_path/*) rp_resolved="${loader_dir}/${rp#@executable_path/}" ;;
                    *) rp_resolved="$rp" ;;
                esac
                if [[ -e "${rp_resolved}/${ref#@rpath/}" ]]; then
                    candidate="${rp_resolved}/${ref#@rpath/}"
                    break
                fi
            done < <(_macho_rpaths "$obj")
            [[ -z "${candidate:-}" ]] && return 1 ;;
        /*) candidate="$ref" ;;
        *) return 1 ;;
    esac
    resolved="$(_canonicalize "$candidate")"
    [[ -n "$resolved" && -f "$resolved" ]] || return 1
    printf '%s' "$resolved"
}

# Recursively vendor a Mach-O closure into <root>/lib with @loader_path/../lib references, then strip
# every non-system LC_RPATH. Closes over the FULL transitive graph (worklist + visited set), resolving
# @loader_path / @executable_path / @rpath / absolute Homebrew refs to their real files. Distinct from
# vendor_nonsystem_dylibs (2-level, kept byte-for-byte for redis/mysql/postgres/nginx): PHP's deep dep
# tree (~35-40 dylibs) needs full closure. $1 = runtime root (holds bin/, lib/, modules/); $2.. =
# initial Mach-O objects already staged under root (e.g. bin/php, modules/intl.so) given as
# "<staged_path>::<origin_dir>" where origin_dir is the keg dir used to resolve @loader_path refs.
vendor_nonsystem_dylibs_recursive() {
    local root="$1"; shift
    local libdir="$root/lib"
    mkdir -p "$libdir"
    local -a work=("$@")
    local visited=" "
    local entry staged origin_dir self_real obj_id ref real base
    while ((${#work[@]})); do
        entry="${work[0]}"; work=("${work[@]:1}")
        staged="${entry%%::*}"; origin_dir="${entry#*::}"
        [[ "$visited" == *" $staged "* ]] && continue
        visited="${visited}${staged} "
        chmod u+w "$staged"
        obj_id="$(otool -D "$staged" | tail -n +2 | head -1)"
        self_real="$(_canonicalize "$staged")"
        while IFS= read -r ref; do
            [[ "$ref" == "$obj_id" ]] && continue
            _is_system_path "$ref" && continue
            case "$ref" in @*|/*) ;; *) continue ;; esac
            real="$(_resolve_ref "$ref" "$origin_dir" "$staged")" || {
                echo "  ! cannot resolve $ref (from $(basename "$staged"))" >&2; continue
            }
            [[ "$real" == "$self_real" ]] && continue
            _is_system_path "$real" && continue
            base="$(basename "$real")"
            if [[ ! -f "$libdir/$base" ]]; then
                cp "$real" "$libdir/$base"
                chmod u+w "$libdir/$base"
                install_name_tool -id "@loader_path/../lib/$base" "$libdir/$base" 2>/dev/null || true
                work+=("$libdir/$base::$(dirname "$real")")
            fi
            install_name_tool -change "$ref" "@loader_path/../lib/$base" "$staged" 2>/dev/null || true
        done < <(otool -L "$staged" | tail -n +2 | awk '{print $1}')
        local rp
        while IFS= read -r rp; do
            [[ -z "$rp" ]] && continue
            _is_system_path "$rp" && continue
            install_name_tool -delete_rpath "$rp" "$staged" 2>/dev/null || true
        done < <(_macho_rpaths "$staged")
        install_name_tool -add_rpath "@loader_path/../lib" "$staged" 2>/dev/null || true
    done
}

# Vendor a standalone extension .so's non-system deps so it is self-contained when dropped into the
# runtime's modules/ dir. Deps the base runtime ALREADY ships (present in <runtime_lib_dir>) are
# referenced via @loader_path/../lib/<base> (modules/ is a sibling of lib/) and NOT copied; deps the
# runtime lacks are copied BESIDE the .so and referenced via @loader_path/<base>, recursing into them.
# $1 = .so path (private deps land in its dir), $2 = the built runtime's lib dir (the "provided" set).
vendor_extension_so() {
    local so="$1" runtime_lib="$2"
    local dir; dir="$(dirname "$so")"
    local -a work=("$so::$(dirname "$(_canonicalize "$so")")")
    local visited=" "
    local entry staged origin_dir self_real obj_id ref real base
    while ((${#work[@]})); do
        entry="${work[0]}"; work=("${work[@]:1}")
        staged="${entry%%::*}"; origin_dir="${entry#*::}"
        [[ "$visited" == *" $staged "* ]] && continue
        visited="${visited}${staged} "
        chmod u+w "$staged"
        obj_id="$(otool -D "$staged" | tail -n +2 | head -1)"
        self_real="$(_canonicalize "$staged")"
        while IFS= read -r ref; do
            [[ "$ref" == "$obj_id" ]] && continue
            _is_system_path "$ref" && continue
            case "$ref" in @*|/*) ;; *) continue ;; esac
            real="$(_resolve_ref "$ref" "$origin_dir" "$staged")" || {
                echo "  ! cannot resolve $ref (from $(basename "$staged"))" >&2; continue
            }
            [[ "$real" == "$self_real" ]] && continue
            _is_system_path "$real" && continue
            base="$(basename "$real")"
            if [[ -f "$runtime_lib/$base" ]]; then
                install_name_tool -change "$ref" "@loader_path/../lib/$base" "$staged" 2>/dev/null || true
                continue
            fi
            if [[ ! -f "$dir/$base" ]]; then
                cp "$real" "$dir/$base"; chmod u+w "$dir/$base"
                install_name_tool -id "@loader_path/$base" "$dir/$base" 2>/dev/null || true
                work+=("$dir/$base::$(dirname "$real")")
            fi
            install_name_tool -change "$ref" "@loader_path/$base" "$staged" 2>/dev/null || true
        done < <(otool -L "$staged" | tail -n +2 | awk '{print $1}')
        local rp
        while IFS= read -r rp; do
            [[ -z "$rp" ]] && continue
            _is_system_path "$rp" && continue
            install_name_tool -delete_rpath "$rp" "$staged" 2>/dev/null || true
        done < <(_macho_rpaths "$staged")
    done
}

# Deep relocatability gate: like relocatable_gate but also rejects @loader_path / @executable_path /
# @rpath refs and LC_RPATH entries that resolve OUTSIDE <root> (the shivammathur bottle ships
# @loader_path/../../../../opt/... refs the basic gate would wrongly pass). $1 = mach-O, $2 = root.
relocatable_gate_deep() {
    local bin="$1" root="$2" root_real loader_dir ref real bad=0 rp rp_real
    root_real="$(_canonicalize "$root")"
    loader_dir="$(dirname "$(_canonicalize "$bin")")"
    while IFS= read -r ref; do
        case "$ref" in
            /usr/lib/*|/System/*) continue ;;
            /*) echo "  ✗ leaked absolute ref in $(basename "$bin"): $ref" >&2; bad=1; continue ;;
        esac
        case "$ref" in
            @loader_path/*) real="$(_canonicalize "${loader_dir}/${ref#@loader_path/}")" ;;
            @executable_path/*) real="$(_canonicalize "${loader_dir}/${ref#@executable_path/}")" ;;
            @rpath/*)
                real=""
                while IFS= read -r rp; do
                    case "$rp" in @loader_path/*) rp="${loader_dir}/${rp#@loader_path/}" ;; esac
                    [[ -e "${rp}/${ref#@rpath/}" ]] && { real="$(_canonicalize "${rp}/${ref#@rpath/}")"; break; }
                done < <(_macho_rpaths "$bin") ;;
            *) continue ;;
        esac
        if [[ -z "$real" || "$real" != "$root_real"/* ]]; then
            echo "  ✗ ref escapes bundle in $(basename "$bin"): $ref -> ${real:-unresolved}" >&2; bad=1
        fi
    done < <(otool -L "$bin" | tail -n +2 | awk '{print $1}')
    while IFS= read -r rp; do
        [[ -z "$rp" ]] && continue
        _is_system_path "$rp" && continue
        case "$rp" in @loader_path/*) rp_real="$(_canonicalize "${loader_dir}/${rp#@loader_path/}")" ;; *) rp_real="$(_canonicalize "$rp")" ;; esac
        if [[ -z "$rp_real" || "$rp_real" != "$root_real"/* ]]; then
            echo "  ✗ LC_RPATH escapes bundle in $(basename "$bin"): $rp" >&2; bad=1
        fi
    done < <(_macho_rpaths "$bin")
    if ((bad)); then return 1; fi
    echo "  ✓ $(basename "$bin") relocatable (deep)"
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
