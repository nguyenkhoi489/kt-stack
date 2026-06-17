import Foundation

/// `mongodump`/`mongorestore` ship in a separate `mongodb-database-tools` package, not the bundled
/// mongod tarball. They install on-demand into `tools/mongodb-database-tools/<version>/bin/` so the
/// existing `RuntimeDownloader` flow (verify sha256 → extract → atomic move) can be reused.
public struct MongoToolsRelease: Sendable, Hashable, Identifiable {
    public let version: String
    public let sha256ByArch: [String: String]
    public let urlByArch: [String: URL]

    public init(version: String, sha256ByArch: [String: String], urlByArch: [String: URL]) {
        self.version = version
        self.sha256ByArch = sha256ByArch
        self.urlByArch = urlByArch
    }

    public var id: String { "mongodb-database-tools-\(version)" }
    public var supportsCurrentArch: Bool { sha256ByArch[ServiceBinaryCatalog.arch] != nil }
    public var sha256: String { sha256ByArch[ServiceBinaryCatalog.arch] ?? "" }
    public var url: URL? { urlByArch[ServiceBinaryCatalog.arch] }
}

public struct MongoToolsCatalog: Sendable {
    public static let toolsName = "mongodb-database-tools"

    public static let pinned = MongoToolsRelease(
        version: "100.10.0",
        sha256ByArch: [
            "arm64":  "PENDING_arm64_MONGO_TOOLS_SHA256",
            "x86_64": "PENDING_x86_64_MONGO_TOOLS_SHA256",
        ],
        urlByArch: [
            "arm64":  URL(string: "https://fastdl.mongodb.org/tools/db/mongodb-database-tools-macos-arm64-100.10.0.zip")!,
            "x86_64": URL(string: "https://fastdl.mongodb.org/tools/db/mongodb-database-tools-macos-x86_64-100.10.0.zip")!,
        ])

    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) { self.paths = paths }

    public var pinnedVersionDir: URL {
        paths.toolVersionDir(Self.toolsName, Self.pinned.version)
    }

    public var availableRelease: MongoToolsRelease? {
        isInstalled ? nil : (Self.pinned.supportsCurrentArch ? Self.pinned : nil)
    }

    public var isInstalled: Bool {
        let fm = FileManager.default
        let dump = pinnedVersionDir.appendingPathComponent("bin/mongodump")
        let restore = pinnedVersionDir.appendingPathComponent("bin/mongorestore")
        return fm.isExecutableFile(atPath: dump.path) && fm.isExecutableFile(atPath: restore.path)
    }

    public func binary(_ relPath: String) -> URL? {
        let url = pinnedVersionDir.appendingPathComponent(relPath)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
}
