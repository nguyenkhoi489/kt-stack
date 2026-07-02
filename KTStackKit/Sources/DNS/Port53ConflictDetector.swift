import Foundation

public struct Port53ConflictDetector {
    public struct Conflict: Equatable, Sendable {
        public let process: String
        public let message: String
    }

    public init() {}

    struct Owner: Equatable {
        let command: String
        let path: String?
    }

    public func check() -> Conflict? {
        guard let owner = Self.udp53Owner(), !Self.isManaged(owner) else { return nil }
        return Conflict(process: owner.command, message: Self.message(for: owner.command))
    }

    // Not a conflict when :53 is held by our managed daemon or a renamed-KDWarm leftover (the helper
    // reaps that on enable). Match by binary path; a foreign dnsmasq at another path IS a conflict.
    // Path can be unreadable (the daemon runs as root, this may run as the user) — then fall back to
    // the bare name so an own/legacy daemon is not misreported as foreign.
    static func isManaged(_ owner: Owner) -> Bool {
        if DNSConstants.isOwnDnsmasq(path: owner.path) || DNSConstants.isLegacyDnsmasq(path: owner.path) {
            return true
        }
        return owner.path == nil && owner.command == "dnsmasq"
    }

    static func message(for process: String) -> String {
        switch process.lowercased() {
        case let p where p.contains("herd") || p.contains("valet"):
            "Another local-dev DNS tool (\(process)) is using port 53. Stop Herd/Valet, then enable KTStack DNS."
        default:
            "Port 53 is already in use by “\(process)”. Stop it, then enable KTStack DNS."
        }
    }

    static func udp53Owner() -> Owner? {
        let text = run("/usr/sbin/lsof", ["-nP", "-iUDP:\(DNSConstants.dnsPort)", "-F", "pc"])
        var pid: String?
        var command: String?
        for line in text.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p" where pid == nil: pid = value
            case "c" where command == nil: command = value
            default: break
            }
        }
        guard let command else { return nil }
        return Owner(command: command, path: pid.flatMap(execPath))
    }

    static func execPath(_ pid: String) -> String? {
        let out = run("/bin/ps", ["-p", pid, "-o", "comm="]).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    private static func run(_ tool: String, _ args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tool)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
