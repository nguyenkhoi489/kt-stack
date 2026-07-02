import Foundation

struct ShellShimWriter {
    let paths: AppSupportPaths

    var helperPath: String {
        paths.shimBinDir.appendingPathComponent("ktstack-resolve").path
    }

    var shimDir: String {
        paths.shimBinDir.path
    }

    private let phpConfigIsolation = """
    __ktphp_dir="${target%/bin/*}"
    __ktphp_ver="${__ktphp_dir##*/}"
    __ktphp_root="${__ktphp_dir%/runtimes/php/*}"
    [ -d "$__ktphp_root/config/php/$__ktphp_ver" ] && export PHPRC="$__ktphp_root/config/php/$__ktphp_ver"
    [ -d "$__ktphp_dir/conf.d" ] && export PHP_INI_SCAN_DIR="$__ktphp_dir/conf.d"
    if [ -d "$__ktphp_dir/modules/imagick-magick/coders" ]; then
        export MAGICK_HOME="$__ktphp_dir/modules/imagick-magick"
        export MAGICK_CODER_MODULE_PATH="$__ktphp_dir/modules/imagick-magick/coders"
        export MAGICK_CODER_FILTER_PATH="$__ktphp_dir/modules/imagick-magick/filters"
        export MAGICK_CONFIGURE_PATH="$__ktphp_dir/modules/imagick-magick/config"
    fi
    """

    // Strip the shim dir from PATH before resolving: the picked runtime and the "command -v"
    // fallback must find the real binary, or the shim would re-exec itself in a loop.
    func directBinaryShim(lang: String) -> String {
        let isolation = lang == "php" ? "\n" + phpConfigIsolation : ""
        return """
        #!/bin/sh
        system_path="$(printf '%s' "$PATH" | tr ':' '\\n' | grep -vxF "\(shimDir)" | paste -sd ':' -)"
        if target="$("\(helperPath)" \(lang) "$PWD" 2>/dev/null)"; then
            export PATH="${target%/*}:$system_path"\(isolation)
            exec "$target" "$@"
        fi
        if fallback="$(PATH="$system_path" command -v \(lang) 2>/dev/null)"; then
            exec "$fallback" "$@"
        fi
        echo "ktstack: \(lang) is not installed — open KTStack to add a runtime" >&2
        exit 127
        """
    }

    func pharShim(name: String, phar: String) -> String {
        """
        #!/bin/sh
        system_path="$(printf '%s' "$PATH" | tr ':' '\\n' | grep -vxF "\(shimDir)" | paste -sd ':' -)"
        phar="\(phar)"
        [ -f "$phar" ] || { echo "ktstack: \(name) is not provisioned — open KTStack to install it" >&2; exit 127; }
        target="$("\(helperPath)" php "$PWD")" || { echo "ktstack: php is not installed" >&2; exit 127; }
        export PATH="${target%/*}:$system_path"
        \(phpConfigIsolation)
        exec "$target" "$phar" "$@"
        """
    }

    var shims: [String: String] {
        [
            "php": directBinaryShim(lang: "php"),
            "node": directBinaryShim(lang: "node"),
            "composer": pharShim(name: "composer", phar: paths.composerPhar.path),
            "wp": pharShim(name: "wp", phar: paths.wpCliPhar.path),
        ]
    }

    func writeShims() throws {
        let fm = FileManager.default
        for (name, body) in shims {
            let url = paths.shimBinDir.appendingPathComponent(name)
            try (body + "\n").data(using: .utf8)!.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }
}
