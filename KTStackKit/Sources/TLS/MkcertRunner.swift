import Foundation

public struct MkcertRunner {
    public let mkcert: URL
    public let caroot: URL

    public init(mkcert: URL, caroot: URL) {
        self.mkcert = mkcert
        self.caroot = caroot
    }

    public var caExists: Bool {
        FileManager.default.fileExists(atPath: caroot.appendingPathComponent("rootCA.pem").path)
    }

    public func install() throws {
        try run(["-install"])
    }

    public func uninstall() throws {
        try run(["-uninstall"])
    }

    public func mint(domain: String, certFile: URL, keyFile: URL) throws {
        try FileManager.default.createDirectory(
            at: certFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try run(Self.mintArgs(domain: domain, certFile: certFile, keyFile: keyFile))
    }

    public static func mintArgs(domain: String, certFile: URL, keyFile: URL) -> [String] {
        ["-cert-file", certFile.path, "-key-file", keyFile.path, domain]
    }

    @discardableResult
    private func run(_ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = mkcert
        proc.arguments = args
        proc.environment = ["CAROOT": caroot.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try FileManager.default.createDirectory(
            at: caroot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard proc.terminationStatus == 0 else {
            throw NSError(
                domain: "KTStack.mkcert",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "mkcert \(args.first ?? "") failed: \(output)"]
            )
        }
        return output
    }
}
