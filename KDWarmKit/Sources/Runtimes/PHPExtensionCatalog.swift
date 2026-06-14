import Foundation

/// How a `.so` is loaded by PHP. A plain `extension=` module resolves via `extension_dir`; a Zend
/// extension (xdebug, profilers, loaders) hooks the Zend engine and MUST be referenced by an ABSOLUTE
/// path in its ini — `extension_dir` does not apply to `zend_extension=`.
public enum PHPExtensionLoadDirective: String, Sendable, Hashable {
    case module = "extension"            // extension=<ext>.so
    case zendExtension = "zend_extension"   // zend_extension=/abs/path/<ext>.so
    public var iniKey: String { rawValue }
}

/// Broad category used only for UI grouping/iconography — not load semantics.
public enum PHPExtensionType: String, Sendable, Hashable, CaseIterable {
    case cache, opcode, graphics, debugger, rpc, runtime, database, network, data, intl, utility
}

/// A PHP extension KDWarm knows about. Two flavors: `isBuiltIn` exts are compiled into the static base
/// (status-only — no install/uninstall, always present); optional exts ship as an independent `.so`
/// layer the user installs/uninstalls (Phase 3). The `id` is the canonical lowercase module name as it
/// appears in `php -m` (e.g. "imagick", "xdebug").
public struct PHPExtension: Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let type: PHPExtensionType
    public let summary: String
    public let loadDirective: PHPExtensionLoadDirective
    public let isBuiltIn: Bool

    public init(id: String, displayName: String, type: PHPExtensionType, summary: String,
                loadDirective: PHPExtensionLoadDirective = .module, isBuiltIn: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.type = type
        self.summary = summary
        self.loadDirective = loadDirective
        self.isBuiltIn = isBuiltIn
    }
}

/// A downloadable optional-extension build: the `.so` artifact URL for one (extension, PHP minor) pair
/// + its expected SHA-256. The `.so` is ABI-locked to the PHP minor, so there is exactly one release
/// per ext × version (no patch dimension — a patch bump keeps the same `ZEND_MODULE_API_NO`).
public struct PHPExtensionRelease: Sendable, Hashable, Identifiable {
    public let extID: String
    public let phpVersion: String
    public let url: URL
    public let sha256: String

    public var id: String { "\(extID)-\(phpVersion)" }

    public init(extID: String, phpVersion: String, url: String, sha256: String) {
        self.extID = extID
        self.phpVersion = phpVersion
        self.url = URL(string: url)!
        self.sha256 = sha256
    }
}

/// Resolved state of an extension for a given installed PHP version. `installedButFailedToLoad`
/// distinguishes a real install from a silent no-op: the `.so` is on disk but `php -m` omits it — an
/// ABI/signature load failure the UI must surface (red-team H2), not hide as "not installed".
public enum PHPExtensionStatus: String, Sendable, Hashable {
    case builtIn               // compiled into the base — status-only
    case installed             // optional `.so` on disk AND loaded (in `php -m`)
    case installedButFailedToLoad   // optional `.so` on disk but absent from `php -m`
    case available             // not installed, a release exists for this version
    case unavailable           // not installed, no release for this version (e.g. swoole on 8.1)
}

/// Optional-extension catalog: static descriptors (built-in + optional) + the Phase-1 download manifest
/// (`.so` per ext × php-version), plus installed-state resolution from the existing `php -m` probe.
/// Pure data/logic — no download or install lifecycle (that is Phase 3).
public struct PHPExtensionCatalog: Sendable {
    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) { self.paths = paths }

    // MARK: Descriptor / manifest lookups

    /// Installable shared extensions (everything not compiled into the base).
    public static func optional() -> [PHPExtension] { descriptors.filter { !$0.isBuiltIn } }

    public static func descriptor(_ extID: String) -> PHPExtension? { descriptors.first { $0.id == extID } }

    /// The downloadable build for one (ext, php-version), or nil when none exists for that pair.
    public func release(_ extID: String, phpVersion: String) -> PHPExtensionRelease? {
        Self.manifest.first { $0.extID == extID && $0.phpVersion == phpVersion }
    }

    // MARK: Installed-state resolution

    /// Extensions an installed PHP version actually LOADS, from `php -m` run with our
    /// `PHP_INI_SCAN_DIR` (the optional-ext conf.d) — a bare `php -m` cannot see a scan-dir `.so`, so it
    /// would mis-report every installed optional ext as failed-to-load. Empty when the binary is missing.
    public func installedExtensions(_ phpVersion: String) -> Set<String> {
        Set(PHPModules.loadedModules(version: phpVersion,
                                     scanDir: paths.phpExtConfDir(version: phpVersion), paths: paths))
    }

    /// Status of `ext` for an installed PHP version. Gathers the live `php -m` set + the on-disk `.so`
    /// presence, then applies the pure rules below.
    public func status(_ ext: PHPExtension, phpVersion: String) -> PHPExtensionStatus {
        status(ext, phpVersion: phpVersion,
               installed: installedExtensions(phpVersion),
               soOnDisk: sharedObjectExists(ext.id, phpVersion: phpVersion))
    }

    /// Pure status rule (inputs injected so it is testable without a real PHP binary):
    /// built-in → always `.builtIn`; otherwise loaded → `.installed`, on-disk-only → load-failure,
    /// else a matching release → `.available`, else `.unavailable`.
    public func status(_ ext: PHPExtension, phpVersion: String,
                       installed: Set<String>, soOnDisk: Bool) -> PHPExtensionStatus {
        if ext.isBuiltIn { return .builtIn }
        if installed.contains(ext.id) { return .installed }
        if soOnDisk { return .installedButFailedToLoad }
        return release(ext.id, phpVersion: phpVersion) != nil ? .available : .unavailable
    }

    /// Whether the optional `.so` is staged under this version's modules dir
    /// (`runtimes/php/<version>/modules/<ext>.so`) — the layout the installer (Phase 3) writes.
    public func sharedObjectExists(_ extID: String, phpVersion: String) -> Bool {
        let so = paths.runtimeDir("php", phpVersion)
            .appendingPathComponent("modules/\(extID).so")
        return FileManager.default.fileExists(atPath: so.path)
    }
}
