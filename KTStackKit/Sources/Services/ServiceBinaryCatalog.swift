import Foundation

public struct ServiceBinaryRelease: Sendable, Hashable, Identifiable {
    public let kind: ServiceKind
    public let version: String

    public let sha256ByArch: [String: String]

    public let urlOverridesByArch: [String: URL]

    public init(
        kind: ServiceKind,
        version: String,
        sha256ByArch: [String: String],
        urlOverridesByArch: [String: URL] = [:]
    ) {
        self.kind = kind
        self.version = version
        self.sha256ByArch = sha256ByArch
        self.urlOverridesByArch = urlOverridesByArch
    }

    public init(kind: ServiceKind, version: String, sha256: String, supports: [String] = ["arm64", "x86_64"]) {
        self.init(
            kind: kind,
            version: version,
            sha256ByArch: Dictionary(uniqueKeysWithValues: supports.map { ($0, sha256) })
        )
    }

    public var id: String {
        "\(kind.rawValue)-\(version)"
    }

    public var fileName: String {
        "\(kind.rawValue)-\(version)-\(ServiceBinaryCatalog.arch).tar.gz"
    }

    public var sha256: String {
        sha256ByArch[ServiceBinaryCatalog.arch] ?? ""
    }

    public var url: URL {
        urlOverridesByArch[ServiceBinaryCatalog.arch]
            ?? ServiceBinaryCatalog.releaseBaseURL.appendingPathComponent(fileName)
    }

    public var supportsCurrentArch: Bool {
        ChecksumVerifier.isResolved(sha256ByArch[ServiceBinaryCatalog.arch])
    }
}

public struct ServiceBinaryCatalog: Sendable {
    public static let releaseBaseURL =
        URL(string: "https://github.com/KTStackAPP/KTStack/releases/download/binaries-v1")!

    public static var arch: String {
        #if arch(arm64)
            return "arm64"
        #else
            return "x86_64"
        #endif
    }

    public static let manifest: [ServiceBinaryRelease] = [
        ServiceBinaryRelease(
            kind: .mysql,
            version: "9.6.0",
            sha256ByArch: [
                "arm64": "e8bf680f8372a9cd4fab38b120753fef1ffb8980d8b5554d64c7186e671616b0",
                "x86_64": "d442e64ffb6a9774a3ae330d99ece8cc252fc59005903291378ef88997a45353",
            ]
        ),
        ServiceBinaryRelease(
            kind: .redis,
            version: "7.4.2",
            sha256ByArch: [
                "arm64": "b9e086c252492561e4a53820589cb893ad07bbd4b1c08f38fcf87836ad1cb6e9",
                "x86_64": "1afcdd01a585f754087a8e3bdf458f9261b0897d81cbbbd45c2fc2b578d789ec",
            ]
        ),
        ServiceBinaryRelease(
            kind: .postgres,
            version: "17.10",
            sha256ByArch: [
                "arm64": "2fc58f9f78376b79f5007bfbbd6f724f5f34d81cd429ef6b0c9696ad8617d698",
                "x86_64": "4e1a6905cc31d135ecea0dafff670dcda3e2493705f00d69cf2f70ec61127651",
            ]
        ),

        ServiceBinaryRelease(
            kind: .mongodb, version: "7.0",
            sha256ByArch: [
                "arm64": "097af3e0486422fc5a3e2e3365d5f23ac53867a408d8eecfa1103c374a8c96de",
                "x86_64": "661200efa742cb67f82a61d857b57e7321959c1ac2a4e53dc0aca65fe60ab876",
            ],
            urlOverridesByArch: [
                "arm64": URL(string: "https://fastdl.mongodb.org/osx/mongodb-macos-arm64-7.0.37.tgz")!,
                "x86_64": URL(string: "https://fastdl.mongodb.org/osx/mongodb-macos-x86_64-7.0.37.tgz")!,
            ]
        ),
        ServiceBinaryRelease(
            kind: .mongodb, version: "6.0",
            sha256ByArch: [
                "arm64": "d0e6c7424cb5aee2e2b2e4c377f66c0e27861ac871b2b13adb809fddf9d1f1b4",
                "x86_64": "e2946068d98850d6be79caebed39211f3e4d4a31d88cb3fa004e375a192d28b5",
            ],
            urlOverridesByArch: [
                "arm64": URL(string: "https://fastdl.mongodb.org/osx/mongodb-macos-arm64-6.0.20.tgz")!,
                "x86_64": URL(string: "https://fastdl.mongodb.org/osx/mongodb-macos-x86_64-6.0.20.tgz")!,
            ]
        ),
        ServiceBinaryRelease(
            kind: .mongodb, version: "8.0",
            sha256ByArch: [
                "arm64": "219e3b3d7b31c049ff7bcf7470d38eff704e56df2ac18d4df78425e2985ccf58",
                "x86_64": "61af8722544f5973e9f5a5f5025460921fe97ca460c61a8d7a9ffabae011982a",
            ],
            urlOverridesByArch: [
                "arm64": URL(string: "https://fastdl.mongodb.org/osx/mongodb-macos-arm64-8.0.4.tgz")!,
                "x86_64": URL(string: "https://fastdl.mongodb.org/osx/mongodb-macos-x86_64-8.0.4.tgz")!,
            ]
        ),
    ]

    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) {
        self.paths = paths
    }

    public static func marker(_ kind: ServiceKind) -> String? {
        switch kind {
        case .redis: "bin/redis-server"
        case .postgres: "bin/postgres"
        case .mysql: "bin/mysqld"
        case .mongodb: "bin/mongod"
        default: nil
        }
    }

    public func installedVersions(_ kind: ServiceKind) -> [String] {
        guard let marker = Self.marker(kind) else { return [] }
        let root = paths.runtimeLangRoot(kind.rawValue)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        return entries
            .filter { fm.isExecutableFile(atPath: root.appendingPathComponent($0).appendingPathComponent(marker).path) }
            .sorted()
    }

    public func availableReleases(_ kind: ServiceKind) -> [ServiceBinaryRelease] {
        let installed = Set(installedVersions(kind))
        return Self.manifest.filter {
            $0.kind == kind && !installed.contains($0.version) && $0.supportsCurrentArch
        }
    }

    public func binary(_ kind: ServiceKind, _ relPath: String, version: String) -> URL? {
        paths.runtimeDir(kind.rawValue, version).appendingPathComponent(relPath)
    }

    public func installedVersion(_ kind: ServiceKind) -> String? {
        installedVersions(kind).max { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    public func isInstalled(_ kind: ServiceKind) -> Bool {
        installedVersion(kind) != nil
    }

    public func binary(_ kind: ServiceKind, _ relPath: String) -> URL? {
        guard let version = installedVersion(kind) else { return nil }
        return binary(kind, relPath, version: version)
    }

    public func availableRelease(_ kind: ServiceKind) -> ServiceBinaryRelease? {
        availableReleases(kind).first
    }

    public func installDir(_ release: ServiceBinaryRelease) -> URL {
        paths.runtimeDir(release.kind.rawValue, release.version)
    }
}
