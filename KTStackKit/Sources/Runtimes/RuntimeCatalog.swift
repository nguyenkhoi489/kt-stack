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
        return Self.manifest.filter { release in
            guard release.language == lang else { return false }
            if !installed.contains(release.version) { return true }
            return lang == .php && needsMigration(release.version)
        }
    }

    private func sourceMarker(_ version: String) -> URL {
        paths.runtimeDir("php", version).appendingPathComponent(".ktstack-source")
    }

    public func needsMigration(_ version: String) -> Bool {
        guard isInstalled(.php, version) else { return false }
        return !FileManager.default.fileExists(atPath: sourceMarker(version).path)
    }

    public func markBottleSource(_ version: String) {
        try? "bottle\n".write(to: sourceMarker(version), atomically: true, encoding: .utf8)
    }

    static let phpRuntimeVersions = ["7.4", "8.0", "8.1", "8.2", "8.3", "8.4"]

    public static let manifest: [RuntimeRelease] = phpRuntimeVersions.map { version in
        RuntimeRelease(language: .php, version: version,
                       url: "https://github.com/KTStackAPP/KTStack/releases/download/binaries-v1/php-\(version)-arm64.tar.gz",
                       sha256: phpArtifactChecksums[version] ?? "")
    } + [
        RuntimeRelease(language: .node, version: "22.22.3",
                       url: "https://nodejs.org/dist/v22.22.3/node-v22.22.3-darwin-arm64.tar.gz",
                       sha256: "0da7ff74ef8611328c8212f17943368713a2ad953fb7d89a8c8a0eae87c23207"),
    ]

    static let phpArtifactChecksums: [String: String] = [
        "7.4": "3bc8620d01c1a7fa92ef51cc1c9d64ea8c97b789f74ef303dd08d5a6133134ec",
        "8.0": "e1ccba12320be5b2633b2a22e5e67384d7eb2b7319b3252d9d1c81c5ad0224e7",
        "8.1": "521db467959d850b1de549bc693e1d60166bd3e0bc07b8fd91194001f2cb2ad8",
        "8.2": "732e6f56d007e13227db9b6d99e0d9f3263e32d1e7c125ad1ffc33aa4b248a41",
        "8.3": "5435cd64bfe98894809a4660acac36f0260aa53155920259e6cfee4a63836d81",
        "8.4": "9a541d703f35e92b298c1c8c69ed2f88d8a300ee870ab8a139bf361e29120538",
    ]
}
