import Foundation

/// Privileged (root) System-Keychain trust operations for the KDWarm local root CA. Accepts ONLY
/// the PUBLIC cert bytes (never the private key) and runs a FIXED `security` command against the
/// System Keychain — no caller-supplied paths or keychain targets.
///
/// Deferred-live like the DNS surface: runs only inside the signed helper (Phase 9). On the dev
/// build the live path is `mkcert -install` (self-elevating, which itself raises the macOS admin
/// prompt), so this is exercised once a Team ID exists.
///
/// Trust model: installing/removing a System trust root as root happens WITHOUT an OS prompt, so the
/// only gate is the XPC peer's code signature (audit-token + Team-ID requirement). The confused-deputy
/// risk (a signed-but-tampered app driving these ops) is mitigated by Hardened Runtime + Library
/// Validation being enabled on the app target — a clean-signed app cannot be dylib-injected. A second
/// human-consent factor (Authorization Services) for these ops is intentionally deferred: the surface
/// is inert until a Team ID is set, and today's live path (mkcert) already prompts.
/// REQUIREMENT before enabling helper signing for production: re-review these CA ops and decide
/// whether to add an Authorization Services consent gate for system-trust changes.
final class HelperCAManager {
    private static let systemKeychain = "/Library/Keychains/System.keychain"

    /// Add the public root cert as a trusted root in the System Keychain.
    func installRootCA(pemData: Data) -> (Bool, String?) {
        // Stage the PUBLIC cert in a root-only dir (0700/0600), not a world-traversable temp dir,
        // to close the TOCTOU window before `security` reads it as root.
        let dir = URL(fileURLWithPath: "/Library/Application Support/KDWarm")
        let tmp = dir.appendingPathComponent(".rootCA-install-\(UUID().uuidString).pem")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try pemData.write(to: tmp)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        } catch {
            return (false, "Could not stage root cert: \(error.localizedDescription)")
        }
        let r = run("/usr/bin/security",
                    ["add-trusted-cert", "-d", "-r", "trustRoot", "-k", Self.systemKeychain, tmp.path])
        return r.status == 0 ? (true, nil) : (false, "security add-trusted-cert failed: \(r.output)")
    }

    /// Remove a specific CA from the System Keychain by EXACT SHA-1 hash — never a name prefix,
    /// so a co-resident mkcert CA (e.g. the user's own) is never deleted by mistake.
    func removeRootCA(certSHA1: String) -> (Bool, String?) {
        let hash = certSHA1.replacingOccurrences(of: ":", with: "").uppercased()
        guard hash.count == 40, hash.allSatisfy({ $0.isHexDigit }) else {
            return (false, "Invalid certificate fingerprint.")
        }
        let r = run("/usr/bin/security", ["delete-certificate", "-Z", hash, Self.systemKeychain])
        // Nonzero when nothing matches — treat as already-removed, but surface a real error otherwise.
        if r.status == 0 { return (true, nil) }
        return r.output.lowercased().contains("not be found") || r.output.isEmpty
            ? (true, nil)
            : (false, "security delete-certificate failed: \(r.output)")
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
