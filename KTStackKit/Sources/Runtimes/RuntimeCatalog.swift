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
    public let urlByArch: [String: URL]
    public let sha256ByArch: [String: String]

    public var id: String { "\(language.rawValue)-\(version)" }

    public init(language: RuntimeLanguage, version: String,
                urlByArch: [String: URL], sha256ByArch: [String: String]) {
        self.language = language
        self.version = version
        self.urlByArch = urlByArch
        self.sha256ByArch = sha256ByArch
    }

    public var url: URL { urlByArch[RuntimeCatalog.arch] ?? urlByArch.values.first! }
    public var sha256: String { sha256ByArch[RuntimeCatalog.arch] ?? "" }

    public var supportsCurrentArch: Bool {
        guard let sha = sha256ByArch[RuntimeCatalog.arch] else { return false }
        return sha.count == 64
    }
}

public struct RuntimeCatalog: Sendable {
    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) { self.paths = paths }

    public static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

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
        return Self.manifest.filter {
            $0.language == lang && !installed.contains($0.version) && $0.supportsCurrentArch
        }
    }

    static let phpRuntimeVersions = ["7.4", "8.0", "8.1", "8.2", "8.3", "8.4"]

    static let releaseBaseURL =
        URL(string: "https://github.com/KTStackAPP/KTStack/releases/download/binaries-v1")!

    private static func phpRelease(_ version: String) -> RuntimeRelease {
        let base = releaseBaseURL
        return RuntimeRelease(
            language: .php, version: version,
            urlByArch: [
                "arm64":  base.appendingPathComponent("php-\(version)-arm64.tar.gz"),
                "x86_64": base.appendingPathComponent("php-\(version)-x86_64.tar.gz"),
            ],
            sha256ByArch: [
                "arm64":  phpArtifactChecksums[version] ?? "",
                "x86_64": phpArtifactChecksumsX86[version] ?? "PENDING_x86_64_PHP",
            ])
    }

    public static let manifest: [RuntimeRelease] = phpRuntimeVersions.map(phpRelease) + [
        RuntimeRelease(
            language: .node, version: "22.22.3",
            urlByArch: [
                "arm64":  URL(string: "https://nodejs.org/dist/v22.22.3/node-v22.22.3-darwin-arm64.tar.gz")!,
                "x86_64": URL(string: "https://nodejs.org/dist/v22.22.3/node-v22.22.3-darwin-x64.tar.gz")!,
            ],
            sha256ByArch: [
                "arm64":  "0da7ff74ef8611328c8212f17943368713a2ad953fb7d89a8c8a0eae87c23207",
                "x86_64": "45830ba752fa0d892c6dcd640946669801293cac820a33591ded40ac075198ec",
            ]),
    ]

    static let phpArtifactChecksums: [String: String] = [
        "7.4": "303e7a893dd5a8e96a863b9cda74a2834121c98903a0f5136e8d59228c3ba2b4",
        "8.0": "d88102cd8c69a25451f3c33d91c64326d0ad5dcc382c25af435d55ccc1897345",
        "8.1": "974a4141c83ba68a146945d2eb15bc18b8165a0f7deb1598d8061f6c87b589cb",
        "8.2": "3ba0e36b504bf202b6764d07a4c3d1f086eb5fa6ecfe037e222cbc269733f2d8",
        "8.3": "7eab0f81067d4cbdcc274df6fa18684f6d2fb73bfc2599573c7a02e4e96064a8",
        "8.4": "5451afde00d8dcbec3d3bdd6136d4a45fb0004d463d2e980d8fdd1340dcab029",
    ]

    static let phpArtifactChecksumsX86: [String: String] = [:]
}
