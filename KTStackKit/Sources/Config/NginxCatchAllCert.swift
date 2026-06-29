import Foundation

public struct NginxCatchAllCert {
    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) {
        self.paths = paths
    }

    public var certFile: URL {
        paths.catchAllCert
    }

    public var keyFile: URL {
        paths.catchAllKey
    }

    public func exists() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: certFile.path) && fm.fileExists(atPath: keyFile.path)
    }

    @discardableResult
    public func ensure() throws -> (cert: URL, key: URL) {
        if exists() { return (certFile, keyFile) }
        try FileManager.default.createDirectory(
            at: paths.caDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        proc.arguments = [
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", keyFile.path, "-out", certFile.path,
            "-days", "3650", "-subj", "/CN=ktstack-catchall",
        ]
        let err = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0, exists() else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NginxConfigWriter.ConfigError.invalidPath("catch-all cert generation failed: \(msg)")
        }
        return (certFile, keyFile)
    }
}
