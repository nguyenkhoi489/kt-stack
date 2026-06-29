import Foundation

public struct Port53ConflictDetector {
    public struct Conflict: Equatable, Sendable {
        public let process: String
        public let message: String
    }

    public init() {}

    public func check() -> Conflict? {
        guard let owner = Self.udp53Owner(), !Self.isOwn(owner) else { return nil }
        return Conflict(process: owner, message: Self.message(for: owner))
    }

    static func isOwn(_ process: String) -> Bool {
        process == "dnsmasq" || process == DNSConstants.daemonLabel
    }

    static func message(for process: String) -> String {
        switch process.lowercased() {
        case let p where p.contains("herd") || p.contains("valet"):
            "Another local-dev DNS tool (\(process)) is using port 53. Stop Herd/Valet, then enable KTStack DNS."
        default:
            "Port 53 is already in use by “\(process)”. Stop it, then enable KTStack DNS."
        }
    }

    static func udp53Owner() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-nP", "-iUDP:\(DNSConstants.dnsPort)", "-F", "c"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("c") {
            return String(line.dropFirst())
        }
        return nil
    }
}
