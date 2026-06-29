import Foundation

/// On-demand fetch for `mongodb-database-tools`. The archive is verified by sha256 and extracted via
/// the existing `RuntimeDownloader` pipeline, then each binary is ad-hoc-signed so it survives the
/// hardened runtime on shipped builds (third-party prebuilt binaries arrive unsigned for our cdhash).
public struct MongoToolsInstaller: Sendable {
    private let paths: AppSupportPaths
    private let downloader: RuntimeDownloader
    private let catalog: MongoToolsCatalog

    public init(paths: AppSupportPaths) {
        self.paths = paths
        downloader = RuntimeDownloader(paths: paths)
        catalog = MongoToolsCatalog(paths: paths)
    }

    public typealias Progress = RuntimeDownloader.Progress

    @discardableResult
    public func install(onProgress: @escaping @Sendable (Progress) -> Void) async throws -> URL {
        guard let release = catalog.availableRelease, let url = release.url else {
            throw DatabaseError.connection("MongoDB database tools aren't available for this CPU.")
        }
        let dest = catalog.pinnedVersionDir
        try paths.ensureDirectoryTree()
        try FileManager.default.createDirectory(
            at: paths.toolsDir(MongoToolsCatalog.toolsName),
            withIntermediateDirectories: true
        )
        let installed = try await downloader.installArchive(
            url: url, sha256: release.sha256,
            into: dest, markerRelPath: "bin/mongodump",
            onProgress: onProgress
        )
        try Self.adHocSign(in: installed)
        return installed
    }

    private static func adHocSign(in installDir: URL) throws {
        let binDir = installDir.appendingPathComponent("bin", isDirectory: true)
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: binDir.path)) ?? []
        for name in entries {
            let target = binDir.appendingPathComponent(name)
            guard fm.isExecutableFile(atPath: target.path) else { continue }
            try runCodesign(target.path)
        }
    }

    private static func runCodesign(_ path: String) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        proc.arguments = ["--force", "--sign", "-", path]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = FileHandle.nullDevice
        try proc.run()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let msg = String(data: err, encoding: .utf8) ?? ""
            throw DatabaseError.connection("Couldn't ad-hoc sign \(path): \(msg)")
        }
    }
}
