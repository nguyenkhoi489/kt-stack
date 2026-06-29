import Foundation

public struct PHPIniStore: Sendable {
    private let paths: AppSupportPaths
    private var fileManager: FileManager {
        .default
    }

    public init(paths: AppSupportPaths = AppSupportPaths()) {
        self.paths = paths
    }

    public func ensureSeeded(version: String) throws {
        let url = paths.phpIni(version: version)
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.createDirectory(
            at: paths.phpIniDir(version: version),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try PHPIniTemplate.default.write(to: url, atomically: true, encoding: .utf8)
    }

    public func read(version: String) throws -> String {
        try ensureSeeded(version: version)
        return try String(contentsOf: paths.phpIni(version: version), encoding: .utf8)
    }

    public func write(version: String, contents: String) throws {
        try fileManager.createDirectory(
            at: paths.phpIniDir(version: version),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = paths.phpIni(version: version)
        if fileManager.fileExists(atPath: url.path) {
            let bak = backupURL(version: version)
            try? fileManager.removeItem(at: bak)
            try? fileManager.copyItem(at: url, to: bak)
        }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    public func resetToDefault(version: String) throws {
        try write(version: version, contents: PHPIniTemplate.default)
    }

    @discardableResult
    public func restoreBackup(version: String) throws -> Bool {
        let bak = backupURL(version: version)
        guard fileManager.fileExists(atPath: bak.path) else { return false }
        let url = paths.phpIni(version: version)
        try? fileManager.removeItem(at: url)
        try fileManager.copyItem(at: bak, to: url)
        return true
    }

    public func validate(version: String, contents: String) -> String? {
        let php = paths.phpBinary(version: version)
        guard fileManager.isExecutableFile(atPath: php.path) else { return nil }
        let tmp = fileManager.temporaryDirectory
            .appendingPathComponent("ktstack-ini-check-\(UUID().uuidString).ini")
        guard (try? contents.write(to: tmp, atomically: true, encoding: .utf8)) != nil else { return nil }
        defer { try? fileManager.removeItem(at: tmp) }

        let proc = Process()
        proc.executableURL = php
        proc.arguments = ["-c", tmp.path, "-v"]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()
        do { try proc.run() } catch { return nil }
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (msg?.isEmpty == false) ? msg : nil
    }

    private func backupURL(version: String) -> URL {
        paths.phpIni(version: version).appendingPathExtension("bak")
    }
}
