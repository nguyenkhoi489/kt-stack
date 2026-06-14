import Foundation

/// Static data for `PHPExtensionCatalog`: the extension descriptors (built-in + optional) and the
/// download manifest of optional `.so` builds. Kept separate from the catalog logic so the data table
/// stays easy to scan and refresh as the build pipeline (scripts/release/build-php-extensions.sh)
/// re-publishes artifacts.
extension PHPExtensionCatalog {

    /// All extensions KDWarm models. Built-ins are compiled into the static base (status-only); the
    /// `optional` set ships as an installable `.so` layer. The built-in list mirrors the base
    /// `EXTENSIONS` in scripts/build-php-static.sh — keep them in sync when the base build changes.
    public static let descriptors: [PHPExtension] = optionalDescriptors + builtInDescriptors

    /// Installable shared extensions, verified end-to-end by Phase 1 (build → relocatability gate →
    /// `php -m` load). xdebug is a Zend extension; swoole is an async CLI runtime, not a per-site fpm
    /// extension (the UI should label it accordingly).
    static let optionalDescriptors: [PHPExtension] = [
        PHPExtension(id: "apcu", displayName: "APCu", type: .cache,
                     summary: "In-memory user-data cache (APC User Cache)."),
        PHPExtension(id: "imagick", displayName: "Imagick", type: .graphics,
                     summary: "ImageMagick bindings for image creation and manipulation."),
        PHPExtension(id: "xdebug", displayName: "Xdebug", type: .debugger,
                     summary: "Step debugger, profiler, and stack traces.",
                     loadDirective: .zendExtension),
        PHPExtension(id: "grpc", displayName: "gRPC", type: .rpc,
                     summary: "gRPC client/server runtime for high-performance RPC."),
        PHPExtension(id: "swoole", displayName: "Swoole", type: .runtime,
                     summary: "Async coroutine runtime — used via CLI (php server.php), not under php-fpm."),
    ]

    /// Compiled into the static base — shown read-only in the manager. Mirrors the base build's
    /// extension matrix (status-only; no install/uninstall).
    static let builtInDescriptors: [PHPExtension] = [
        ("fileinfo", "Fileinfo", PHPExtensionType.utility), ("opcache", "OPcache", .opcode),
        ("memcached", "Memcached", .cache), ("redis", "Redis", .cache), ("exif", "EXIF", .graphics),
        ("intl", "Intl", .intl), ("xsl", "XSL", .data), ("mbstring", "Mbstring", .data),
        ("xlswriter", "XLSWriter", .data), ("pgsql", "pgSQL", .database), ("ssh2", "SSH2", .network),
        ("xhprof", "XHProf", .debugger), ("protobuf", "Protobuf", .data),
        ("pdo_pgsql", "PDO pgSQL", .database), ("readline", "Readline", .utility),
        ("snmp", "SNMP", .network), ("ldap", "LDAP", .network), ("bz2", "Bzip2", .data),
        ("sysvshm", "SysV SHM", .utility), ("calendar", "Calendar", .utility), ("gmp", "GMP", .data),
        ("sysvmsg", "SysV Msg", .utility), ("zstd", "Zstd", .data), ("event", "Event", .runtime),
    ].map { PHPExtension(id: $0.0, displayName: $0.1, type: $0.2, summary: "Compiled into the base PHP.",
                         isBuiltIn: true) }

    /// Optional `.so` download manifest — one entry per (ext, php-version), produced + published by
    /// Phase 1 (scripts/release/build-php-extensions.sh → publish-artifacts.sh @ binaries-v1). swoole
    /// has no 8.1 build (Swoole 6 does not compile on PHP 8.1). Refresh sha256 when artifacts re-publish.
    public static let manifest: [PHPExtensionRelease] = [
        ext("apcu", "8.4", "947bbeda839c114981fd5de64ecd5eb56fdf48effefd62ca62649cc50f7f3f14"),
        ext("apcu", "8.3", "9c471be1a86e2f5e0816d2f38a50df0812ddbf91fe7f60daa93e56bd77982024"),
        ext("apcu", "8.1", "24a27086a0c25e935d0ec919c2aa0beaf24e6426e7fdb6b0579b44bc05c89e02"),
        ext("imagick", "8.4", "df79f1ffe8be6074644eafba69faf02b6e982015b85412237c4d2a357fdce2b5"),
        ext("imagick", "8.3", "8cc47eb409b14dde07a8a1005680e45bf22053d711a583b2a1503fe1dd4e0a57"),
        ext("imagick", "8.1", "7c201c635b06f7ec851a8e061190047da839aa4cf83596519a2eaa058f5e83e5"),
        ext("xdebug", "8.4", "0c5e83f9c65d6607c4a38681800d16f34bf0b08e07cff7131d423272551bdc97"),
        ext("xdebug", "8.3", "c668a709aabded866547e8a0b6592772074052aadc398aa68881411d250c5979"),
        ext("xdebug", "8.1", "37b6df46467fec31616fa92de4320691a493ec7d2959d2248ef35041e4aaa20c"),
        ext("grpc", "8.4", "2c7115b2eeebabfb792aaa7866ae7290f2c4b49dce8152bd34ef5125f668a588"),
        ext("grpc", "8.3", "c74de657774decca1b0dd3ea2ef2479841006488c5ba44df1dff7549ba45f729"),
        ext("grpc", "8.1", "76c332ff6a5206978d4b0c015be90b08a6bbc1165eb552f638d50c19ed9401d1"),
        ext("swoole", "8.4", "6a53e17961a77832699397f31c02d7ec21e9b59dd952a05510e68770693469ee"),
        ext("swoole", "8.3", "9f244aa1b0cc5afb88fdd3bc2a75b2de39572de99e801d31ad2005da59a73686"),
    ]

    /// Build a release whose URL follows the published artifact convention
    /// `…/releases/download/binaries-v1/php-ext-<ext>-<ver>-arm64.tar.gz`.
    private static func ext(_ id: String, _ version: String, _ sha256: String) -> PHPExtensionRelease {
        PHPExtensionRelease(
            extID: id, phpVersion: version,
            url: "https://github.com/nguyenkhoi489/kd-warm/releases/download/binaries-v1/php-ext-\(id)-\(version)-arm64.tar.gz",
            sha256: sha256)
    }
}
