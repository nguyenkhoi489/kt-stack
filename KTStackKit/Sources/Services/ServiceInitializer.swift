import Foundation

public enum ServiceInitializer {
    public struct InitError: LocalizedError {
        public let tool: String
        public let output: String
        public var errorDescription: String? {
            "\(tool) initialization failed: \(output)"
        }
    }

    public static func isInitialized(_ dir: URL, marker: String? = nil) -> Bool {
        let fm = FileManager.default
        if let marker { return fm.fileExists(atPath: dir.appendingPathComponent(marker).path) }
        guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return false }
        return !items.isEmpty
    }

    public static func ensureDir(_ dir: URL) throws {
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
    }

    public static func run(_ executable: URL, _ arguments: [String], tool: String) throws {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch {
            throw InitError(tool: tool, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw InitError(tool: tool, output: String(data: data, encoding: .utf8) ?? "exit \(proc.terminationStatus)")
        }
    }
}

public struct ServiceNotInstalled: LocalizedError {
    public let kind: ServiceKind
    public init(_ kind: ServiceKind) {
        self.kind = kind
    }

    public var errorDescription: String? {
        "\(kind.displayName) is not bundled in this build yet."
    }
}
