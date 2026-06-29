import Foundation

public struct BinaryStager {
    public enum StageError: LocalizedError {
        case missingSource(String)
        case signatureInvalid(String)
        case copyFailed(String, String)

        public var errorDescription: String? {
            switch self {
            case let .missingSource(p): "Bundled binary not found: \(p)"
            case let .signatureInvalid(p): "Code signature check failed for \(p) — refusing to run a possibly tampered binary."
            case let .copyFailed(n, m): "Could not stage \(n): \(m)"
            }
        }
    }

    public static let binBinaries = ["nginx", "dnsmasq", "mkcert"]

    public static let optionalBinaryNames = ["mailpit"]

    private let bundleBinDir: URL
    private let paths: AppSupportPaths
    private let fileManager: FileManager

    public init(bundleBinDir: URL, paths: AppSupportPaths, fileManager: FileManager = .default) {
        self.bundleBinDir = bundleBinDir
        self.paths = paths
        self.fileManager = fileManager
    }

    public func stageIfNeeded() throws {
        try paths.ensureDirectoryTree(fileManager: fileManager)
        RestoreStagingArea(paths: paths).sweepOrphans(keeping: [])
        for name in Self.binBinaries {
            try stage(
                from: bundleBinDir.appendingPathComponent(name),
                to: paths.bin.appendingPathComponent(name),
                displayName: name
            )
        }
        try stagePHPRuntimes()
        for name in Self.optionalBinaryNames where fileManager.isReadableFile(
            atPath: bundleBinDir.appendingPathComponent(name).path
        ) {
            try stage(
                from: bundleBinDir.appendingPathComponent(name),
                to: paths.bin.appendingPathComponent(name),
                displayName: name
            )
        }
    }

    private func stagePHPRuntimes() throws {
        if fileManager.isReadableFile(atPath: bundleBinDir.appendingPathComponent("php-fpm").path) {
            try stagePHPVersion(BundledPHP.defaultVersion, fpmSource: "php-fpm", cliSource: "php")
        }

        for version in BundledPHP.plannedVersions where version != BundledPHP.defaultVersion {
            let fpm = "php-fpm-\(version)"
            guard fileManager.isReadableFile(atPath: bundleBinDir.appendingPathComponent(fpm).path) else { continue }
            try stagePHPVersion(version, fpmSource: fpm, cliSource: "php-\(version)")
        }
    }

    private func stagePHPVersion(_ version: String, fpmSource: String, cliSource: String) throws {
        let binDir = paths.runtimeBin("php", version)
        try fileManager.createDirectory(
            at: binDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try stage(
            from: bundleBinDir.appendingPathComponent(fpmSource),
            to: binDir.appendingPathComponent("php-fpm"),
            displayName: fpmSource
        )

        let cli = bundleBinDir.appendingPathComponent(cliSource)
        if fileManager.isReadableFile(atPath: cli.path) {
            try stage(from: cli, to: binDir.appendingPathComponent("php"), displayName: cliSource)
        }
    }

    private func stage(from source: URL, to dest: URL, displayName name: String) throws {
        guard fileManager.isReadableFile(atPath: source.path) else {
            throw StageError.missingSource(source.path)
        }
        try enforceSignature(at: source)

        if try shouldRestage(source: source, dest: dest) {
            do {
                if fileManager.fileExists(atPath: dest.path) {
                    try fileManager.removeItem(at: dest)
                }
                try fileManager.copyItem(at: source, to: dest)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
            } catch {
                throw StageError.copyFailed(name, error.localizedDescription)
            }
        }

        try enforceSignature(at: dest)
    }

    private func enforceSignature(at url: URL) throws {
        guard !Self.verifySignature(at: url) else { return }
        #if DEBUG
            NSLog("KTStack: skipping signature check for unsigned binary in DEBUG build: \(url.path)")
        #else
            throw StageError.signatureInvalid(url.path)
        #endif
    }

    private func shouldRestage(source: URL, dest: URL) throws -> Bool {
        guard fileManager.fileExists(atPath: dest.path) else { return true }
        let s = try fileManager.attributesOfItem(atPath: source.path)
        let d = try fileManager.attributesOfItem(atPath: dest.path)
        let sSize = (s[.size] as? Int) ?? -1
        let dSize = (d[.size] as? Int) ?? -2
        if sSize != dSize { return true }
        let sDate = (s[.modificationDate] as? Date) ?? .distantFuture
        let dDate = (d[.modificationDate] as? Date) ?? .distantPast
        return sDate > dDate
    }

    static func verifySignature(at url: URL) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        proc.arguments = ["--verify", "--strict", url.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
}
