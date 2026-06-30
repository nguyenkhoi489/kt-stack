import Foundation

public struct NginxUserIncludeStore: Sendable {
    private let paths: AppSupportPaths
    private var fileManager: FileManager { .default }

    public init(paths: AppSupportPaths = AppSupportPaths()) {
        self.paths = paths
    }

    public func ensureSeeded() throws {
        guard !fileManager.fileExists(atPath: paths.nginxUserConf.path) else { return }
        try fileManager.createDirectory(
            at: paths.nginxConfigDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try NginxUserIncludeTemplate.default.write(
            to: paths.nginxUserConf,
            atomically: true,
            encoding: .utf8
        )
    }

    public func read() throws -> String {
        try ensureSeeded()
        return try String(contentsOf: paths.nginxUserConf, encoding: .utf8)
    }

    public func write(contents: String) throws {
        try fileManager.createDirectory(
            at: paths.nginxConfigDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = paths.nginxUserConf
        if fileManager.fileExists(atPath: url.path) {
            let bak = backupURL
            try? fileManager.removeItem(at: bak)
            try? fileManager.copyItem(at: url, to: bak)
        }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    public func resetToDefault() throws {
        try write(contents: NginxUserIncludeTemplate.default)
    }

    @discardableResult
    public func restoreBackup() throws -> Bool {
        let bak = backupURL
        guard fileManager.fileExists(atPath: bak.path) else { return false }
        let url = paths.nginxUserConf
        try? fileManager.removeItem(at: url)
        try fileManager.copyItem(at: bak, to: url)
        return true
    }

    private var backupURL: URL {
        paths.nginxUserConf.appendingPathExtension("bak")
    }
}
