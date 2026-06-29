import Foundation

public enum PHPExtensionLoadDirective: String, Sendable, Hashable {
    case module = "extension" // extension=<ext>.so
    case zendExtension = "zend_extension" // zend_extension=/abs/path/<ext>.so
    public var iniKey: String {
        rawValue
    }
}

public enum PHPExtensionType: String, Sendable, Hashable, CaseIterable {
    case cache, opcode, graphics, debugger, rpc, runtime, database, network, data, intl, utility
}

public struct PHPExtension: Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let type: PHPExtensionType
    public let summary: String
    public let loadDirective: PHPExtensionLoadDirective
    public let isBuiltIn: Bool

    public init(
        id: String,
        displayName: String,
        type: PHPExtensionType,
        summary: String,
        loadDirective: PHPExtensionLoadDirective = .module,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.type = type
        self.summary = summary
        self.loadDirective = loadDirective
        self.isBuiltIn = isBuiltIn
    }
}

public struct PHPExtensionRelease: Sendable, Hashable, Identifiable {
    public let extID: String
    public let phpVersion: String
    public let sha256ByArch: [String: String]

    public var id: String {
        "\(extID)-\(phpVersion)"
    }

    public init(extID: String, phpVersion: String, sha256ByArch: [String: String]) {
        self.extID = extID
        self.phpVersion = phpVersion
        self.sha256ByArch = sha256ByArch
    }

    public var fileName: String {
        "php-ext-\(extID)-\(phpVersion)-\(RuntimeCatalog.arch).tar.gz"
    }

    public var url: URL {
        URL(string: "https://github.com/KTStackAPP/KTStack/releases/download/binaries-v1/\(fileName)")!
    }

    public var sha256: String {
        sha256ByArch[RuntimeCatalog.arch] ?? ""
    }

    public var supportsCurrentArch: Bool {
        ChecksumVerifier.isResolved(sha256ByArch[RuntimeCatalog.arch])
    }
}

public enum PHPExtensionStatus: String, Sendable, Hashable {
    case builtIn
    case installed
    case installedButFailedToLoad
    case available
    case unavailable
}

public struct PHPExtensionCatalog: Sendable {
    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) {
        self.paths = paths
    }

    public static func optional() -> [PHPExtension] {
        descriptors.filter { !$0.isBuiltIn }
    }

    public static func descriptor(_ extID: String) -> PHPExtension? {
        descriptors.first { $0.id == extID }
    }

    public func release(_ extID: String, phpVersion: String) -> PHPExtensionRelease? {
        Self.manifest.first { $0.extID == extID && $0.phpVersion == phpVersion && $0.supportsCurrentArch }
    }

    public func installedExtensions(_ phpVersion: String) -> Set<String> {
        Set(PHPModules.loadedModules(
            version: phpVersion,
            scanDir: paths.phpExtConfDir(version: phpVersion),
            paths: paths
        ))
    }

    public func status(_ ext: PHPExtension, phpVersion: String) -> PHPExtensionStatus {
        status(
            ext,
            phpVersion: phpVersion,
            installed: installedExtensions(phpVersion),
            soOnDisk: sharedObjectExists(ext.id, phpVersion: phpVersion)
        )
    }

    public func status(
        _ ext: PHPExtension,
        phpVersion: String,
        installed: Set<String>,
        soOnDisk: Bool
    ) -> PHPExtensionStatus {
        if ext.isBuiltIn { return .builtIn }
        if installed.contains(ext.id) { return .installed }
        if soOnDisk { return .installedButFailedToLoad }
        return release(ext.id, phpVersion: phpVersion) != nil ? .available : .unavailable
    }

    public func sharedObjectExists(_ extID: String, phpVersion: String) -> Bool {
        let so = paths.runtimeDir("php", phpVersion)
            .appendingPathComponent("modules/\(extID).so")
        return FileManager.default.fileExists(atPath: so.path)
    }
}
