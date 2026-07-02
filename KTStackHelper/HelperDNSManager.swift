import Foundation

final class HelperDNSManager {
    func enableDNS(tld: String) -> (Bool, String?) {
        guard let resolverPath = try? DNSConstants.resolverPathChecked(for: tld) else {
            return (false, "Invalid TLD.")
        }
        if let owner = port53Owner(), !ownerIsTakeable(owner) {
            return (false, "Port 53 is already held by “\(owner.command)”. Stop it (another DNS tool?) and retry.")
        }
        do {
            try writeRootFile(DNSConstants.dnsmasqConf(for: tld), to: DNSConstants.dnsmasqConfPath, mode: 0o644)
            try writeRootFile(DNSConstants.daemonPlist, to: DNSConstants.daemonPlistPath, mode: 0o644)
            try writeRootFile(DNSConstants.resolverContents, to: resolverPath, mode: 0o644)
            try bootstrapDaemon()
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func disableDNS(tld: String) -> (Bool, String?) {
        guard let resolverPath = try? DNSConstants.resolverPathChecked(for: tld) else {
            return (false, "Invalid TLD.")
        }
        bootoutDaemon()
        try? FileManager.default.removeItem(atPath: resolverPath)
        try? FileManager.default.removeItem(atPath: DNSConstants.daemonPlistPath)
        return (true, nil)
    }

    func resetDNS(tld: String) -> (Bool, String?) {
        _ = disableDNS(tld: tld)
        return enableDNS(tld: tld)
    }

    func setTLD(old: String, new: String) -> (Bool, String?) {
        guard let oldResolver = try? DNSConstants.resolverPathChecked(for: old),
              (try? DNSConstants.validatedTLD(new)) != nil
        else {
            return (false, "Invalid TLD.")
        }
        if old != new {
            try? FileManager.default.removeItem(atPath: oldResolver)
        }
        let result = enableDNS(tld: new)
        _ = run("/usr/bin/dscacheutil", ["-flushcache"])
        return result
    }

    func status(tld: String) -> (resolverPresent: Bool, dnsmasqRunning: Bool, conflict: String?) {
        guard DNSConstants.isValidTLD(tld) else { return (false, false, nil) }
        let resolver = FileManager.default.fileExists(atPath: DNSConstants.resolverPath(for: tld))
        let running = launchctl(["print", "system/\(DNSConstants.daemonLabel)"]).status == 0
        let owner = port53Owner()
        let conflict = (owner == nil || ownerIsTakeable(owner!)) ? nil : owner!.command
        return (resolver, running, conflict)
    }

    // We may take over :53 from our own stale daemon or a renamed-KDWarm leftover (cleaned in
    // bootstrapDaemon). A foreign dnsmasq/other tool with a readable non-matching path is refused.
    private func ownerIsTakeable(_ owner: PortOwner) -> Bool {
        if DNSConstants.isOwnDnsmasq(path: owner.path) || DNSConstants.isLegacyDnsmasq(path: owner.path) {
            return true
        }
        // Path unreadable but it is a dnsmasq: assume it is one of ours (bootstrapDaemon reaps both
        // labels before binding). A named non-dnsmasq process is a real conflict.
        return owner.path == nil && owner.command == "dnsmasq"
    }

    private func bootstrapDaemon() throws {
        // Free :53 from a renamed-KDWarm leftover, then replace any prior own instance.
        bootoutLegacyDaemon()
        bootoutDaemon()
        let r = launchctl(["bootstrap", "system", DNSConstants.daemonPlistPath])
        guard r.status == 0 else {
            throw NSError(
                domain: "KTStackHelper",
                code: Int(r.status),
                userInfo: [NSLocalizedDescriptionKey: "launchctl bootstrap failed: \(r.output)"]
            )
        }
    }

    private func bootoutDaemon() {
        _ = launchctl(["bootout", "system/\(DNSConstants.daemonLabel)"])
    }

    private func bootoutLegacyDaemon() {
        _ = launchctl(["bootout", "system/\(DNSConstants.legacyDaemonLabel)"])
        try? FileManager.default.removeItem(atPath: DNSConstants.legacyDaemonPlistPath)
    }

    private func writeRootFile(_ contents: String, to path: String, mode: Int) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
    }

    @discardableResult
    private func launchctl(_ args: [String]) -> (status: Int32, output: String) {
        run("/bin/launchctl", args)
    }

    private struct PortOwner {
        let command: String
        let path: String?
    }

    private func port53Owner() -> PortOwner? {
        let r = run("/usr/sbin/lsof", ["-nP", "-iUDP:\(DNSConstants.dnsPort)", "-F", "pc"])
        var pid: String?
        var command: String?
        for line in r.output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p" where pid == nil: pid = value
            case "c" where command == nil: command = value
            default: break
            }
        }
        guard let command else { return nil }
        return PortOwner(command: command, path: pid.flatMap(execPath))
    }

    // Full executable path of a pid (ps -o comm= prints the path on macOS), to tell our managed
    // dnsmasq apart from a foreign one that shares the "dnsmasq" name.
    private func execPath(pid: String) -> String? {
        let out = run("/bin/ps", ["-p", pid, "-o", "comm="]).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    private func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tool)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
