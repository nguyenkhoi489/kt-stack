import Foundation

public enum RuntimeLanguage: String, CaseIterable, Sendable, Identifiable, Hashable {
    case php, node

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .php:  return "PHP"
        case .node: return "Node.js"
        }
    }

    public var symbolName: String {
        switch self {
        case .php:  return "chevron.left.forwardslash.chevron.right"
        case .node: return "shippingbox"
        }
    }

    public var isBundled: Bool { false }

    public var executableRelPath: String {
        switch self {
        case .php:  return "bin/php-fpm"
        case .node: return "bin/node"
        }
    }
}

public struct RuntimeRelease: Sendable, Hashable, Identifiable {
    public let language: RuntimeLanguage
    public let version: String
    public let url: URL
    public let sha256: String

    public var id: String { "\(language.rawValue)-\(version)" }

    public init(language: RuntimeLanguage, version: String, url: String, sha256: String) {
        self.language = language
        self.version = version
        self.url = URL(string: url)!
        self.sha256 = sha256
    }
}

public struct RuntimeCatalog: Sendable {
    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) { self.paths = paths }

    public func installedVersions(_ lang: RuntimeLanguage) -> [String] {
        let root = paths.runtimeLangRoot(lang.rawValue)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        return entries
            .filter { fm.isExecutableFile(atPath: root.appendingPathComponent($0)
                .appendingPathComponent(lang.executableRelPath).path) }
            .sorted()
    }

    public func isInstalled(_ lang: RuntimeLanguage, _ version: String) -> Bool {
        installedVersions(lang).contains(version)
    }

    public func availableReleases(_ lang: RuntimeLanguage) -> [RuntimeRelease] {
        let installed = Set(installedVersions(lang))
        return Self.manifest.filter { $0.language == lang && !installed.contains($0.version) }
    }

    public static let manifest: [RuntimeRelease] = [

        RuntimeRelease(language: .php, version: "8.4",
                       url: "https://github.com/KTStackAPP/KTStack/releases/download/binaries-v1/php-8.4-arm64.tar.gz",
                       sha256: "f56545ca569e50853a2498f59e618e5a6b81072188f4249e3e80bb71b760ee66"),
        RuntimeRelease(language: .php, version: "8.3",
                       url: "https://github.com/KTStackAPP/KTStack/releases/download/binaries-v1/php-8.3-arm64.tar.gz",
                       sha256: "2b1a15bf9c6a7a832f500ad5a40c8fc6abdbea6cfe39e69543e09dc594920735"),
        RuntimeRelease(language: .php, version: "8.1",
                       url: "https://github.com/KTStackAPP/KTStack/releases/download/binaries-v1/php-8.1-arm64.tar.gz",
                       sha256: "f88e284137a18934fcf131f1b9268269583c93fe8473c34f3484d2fed97fe3b8"),
        RuntimeRelease(language: .node, version: "22.22.3",
                       url: "https://nodejs.org/dist/v22.22.3/node-v22.22.3-darwin-arm64.tar.gz",
                       sha256: "0da7ff74ef8611328c8212f17943368713a2ad953fb7d89a8c8a0eae87c23207"),
    ]
}
