import Foundation

public struct SudoFallbackInstaller {
    public let bundledDnsmasq: URL

    public let tld: String

    public init(bundledDnsmasq: URL, tld: String = AppPreferences.defaultTLD) {
        self.bundledDnsmasq = bundledDnsmasq
        self.tld = tld
    }

    public func installScript() -> String {
        "#!/bin/bash\nset -euo pipefail\n" + installBody(tld: tld)
    }

    public func uninstallScript() -> String {
        "#!/bin/bash\nset -uo pipefail\n" + uninstallBody(tld: tld)
    }

    public func resetScript() -> String {
        "#!/bin/bash\nset -uo pipefail\n" + uninstallBody(tld: tld) + "\nset -e\n" + installBody(tld: tld)
    }

    public func setTLDScript(old: String, new: String) -> String {
        let removeOld = old == new ? "" : "rm -f \(q(DNSConstants.resolverPath(for: old)))\n"
        return "#!/bin/bash\nset -euo pipefail\n"
            + removeOld
            + installBody(tld: new)
            + "\n/usr/bin/dscacheutil -flushcache || true\n"
    }

    private func installBody(tld: String) -> String {
        """
        mkdir -p \(q("\(DNSConstants.supportDir)/bin"))
        cp \(q(bundledDnsmasq.path)) \(q(DNSConstants.dnsmasqBinaryPath))
        chmod 0755 \(q(DNSConstants.dnsmasqBinaryPath))

        cat > \(q(DNSConstants.dnsmasqConfPath)) <<'KTSTACK_CONF'
        \(DNSConstants.dnsmasqConf(for: tld))
        KTSTACK_CONF

        mkdir -p /etc/resolver
        cat > \(q(DNSConstants.resolverPath(for: tld))) <<'KTSTACK_RESOLVER'
        \(DNSConstants.resolverContents)KTSTACK_RESOLVER

        cat > \(q(DNSConstants.daemonPlistPath)) <<'KTSTACK_PLIST'
        \(DNSConstants.daemonPlist)
        KTSTACK_PLIST
        chmod 0644 \(q(DNSConstants.daemonPlistPath))

        launchctl bootout system/\(DNSConstants.daemonLabel) 2>/dev/null || true
        launchctl bootstrap system \(q(DNSConstants.daemonPlistPath))
        echo "KTStack DNS enabled — *.\(tld) resolves to 127.0.0.1"
        """
    }

    private func uninstallBody(tld: String) -> String {
        """
        launchctl bootout system/\(DNSConstants.daemonLabel) 2>/dev/null || true
        rm -f \(q(DNSConstants.resolverPath(for: tld))) \(q(DNSConstants.daemonPlistPath)) \(q(DNSConstants.dnsmasqConfPath))
        rm -f \(q(DNSConstants.dnsmasqBinaryPath))
        echo "KTStack DNS disabled — *.\(tld) no longer resolves locally"
        """
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func q(_ value: String) -> String {
        Self.shellQuote(value)
    }

    @discardableResult
    public func writeScripts(to dir: URL) throws -> (install: URL, uninstall: URL, reset: URL) {
        _ = try DNSConstants.validatedTLD(tld)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let install = dir.appendingPathComponent("install.sh")
        let uninstall = dir.appendingPathComponent("uninstall.sh")
        let reset = dir.appendingPathComponent("reset.sh")
        try installScript().write(to: install, atomically: true, encoding: .utf8)
        try uninstallScript().write(to: uninstall, atomically: true, encoding: .utf8)
        try resetScript().write(to: reset, atomically: true, encoding: .utf8)
        for s in [install, uninstall, reset] {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: s.path)
        }
        return (install, uninstall, reset)
    }

    public static func freshStagingDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ktstack-dns-\(UUID().uuidString)")
    }

    public func runInstallWithAdminPrivileges() throws {
        try runAsAdmin(writeScripts(to: Self.freshStagingDir()).install.path)
    }

    public func runUninstallWithAdminPrivileges() throws {
        try runAsAdmin(writeScripts(to: Self.freshStagingDir()).uninstall.path)
    }

    public func runResetWithAdminPrivileges() throws {
        try runAsAdmin(writeScripts(to: Self.freshStagingDir()).reset.path)
    }

    public func runSetTLDWithAdminPrivileges(old: String, new: String) throws {
        _ = try DNSConstants.validatedTLD(old)
        _ = try DNSConstants.validatedTLD(new)
        let dir = Self.freshStagingDir()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let script = dir.appendingPathComponent("set-tld.sh")
        try setTLDScript(old: old, new: new).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        try runAsAdmin(script.path)
    }

    private func runAsAdmin(_ scriptPath: String) throws {
        let asEscaped = scriptPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"/bin/bash \" & quoted form of \"\(asEscaped)\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", osa]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw NSError(
                domain: "KTStack",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Admin authorization was cancelled or failed."]
            )
        }
    }
}
