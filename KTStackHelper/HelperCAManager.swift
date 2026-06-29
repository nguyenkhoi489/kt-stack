import Foundation

final class HelperCAManager {
    private static let systemKeychain = "/Library/Keychains/System.keychain"

    func installRootCA(pemData: Data) -> (Bool, String?) {
        if let rejection = RootCAConstraint.validateKTStackRootCA(pemData: pemData) {
            return (false, rejection.message)
        }
        let dir = URL(fileURLWithPath: "/Library/Application Support/KTStack")
        let tmp = dir.appendingPathComponent(".rootCA-install-\(UUID().uuidString).pem")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try pemData.write(to: tmp)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        } catch {
            return (false, "Could not stage root cert: \(error.localizedDescription)")
        }
        let r = run(
            "/usr/bin/security",
            ["add-trusted-cert", "-d", "-r", "trustRoot", "-k", Self.systemKeychain, tmp.path]
        )
        return r.status == 0 ? (true, nil) : (false, "security add-trusted-cert failed: \(r.output)")
    }

    func removeRootCA(certSHA1: String) -> (Bool, String?) {
        let hash = certSHA1.replacingOccurrences(of: ":", with: "").uppercased()
        guard hash.count == 40, hash.allSatisfy(\.isHexDigit) else {
            return (false, "Invalid certificate fingerprint.")
        }
        let r = run("/usr/bin/security", ["delete-certificate", "-Z", hash, Self.systemKeychain])

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
