import Foundation

/// Input-hardening for the dump subprocess. Credentials NEVER ride argv/env (`ps`-visible on a
/// non-sandboxed app) — they go in a `--defaults-extra-file` written mode 0600. The validators below
/// guard every value that reaches argv (db/table/host) or the defaults file (user/host/password),
/// so a name can't smuggle an extra option, break the ini format, or escape into a path.
extension DumpService {
    /// Reject anything that could turn a name into an option, a path, or an injection into SQL/ini:
    /// empty, leading `-`, `=`, path separators, quotes/backticks, or any control char. Length-capped.
    static func validateIdentifier(_ value: String, label: String, maxLength: Int = 64) throws {
        guard !value.isEmpty else {
            throw DatabaseError.connection("Empty \(label) name")
        }
        guard value.count <= maxLength else {
            throw DatabaseError.connection("\(label) name is too long")
        }
        guard !value.hasPrefix("-") else {
            throw DatabaseError.connection("\(label) name can't start with '-'")
        }
        try requireNoIllegalScalars(value, label: label, illegal: "=/\\`'\"")
    }

    /// Hosts allow dots/colons (IPv6) but not separators, `=`, spaces, or control chars.
    static func validateHost(_ host: String) throws {
        guard !host.isEmpty, host.count <= 255 else {
            throw DatabaseError.connection("Invalid host")
        }
        guard !host.hasPrefix("-") else {
            throw DatabaseError.connection("Host can't start with '-'")
        }
        try requireNoIllegalScalars(host, label: "host", illegal: "=/\\ ")
    }

    private static func requireNoIllegalScalars(_ value: String, label: String, illegal: String) throws {
        let illegalSet = Set(illegal.unicodeScalars)
        for scalar in value.unicodeScalars {
            // Control chars (incl. NUL/newline/tab) and the explicit illegal set are both rejected.
            if scalar.value < 0x20 || illegalSet.contains(scalar) {
                throw DatabaseError.connection("Illegal character in \(label) name")
            }
        }
    }

    /// Build the `[client]` section for a `--defaults-extra-file`. User/host are validated; a newline
    /// in the password is rejected because the ini format is line-delimited and couldn't carry it.
    static func defaultsContent(
        user: String,
        host: String,
        port: Int,
        password: String?,
        tlsMode: TLSMode = .prefer
    ) throws -> String {
        try validateIdentifier(user, label: "user", maxLength: 255)
        try validateHost(host)
        if let password, password.contains(where: { $0 == "\n" || $0 == "\r" }) {
            throw DatabaseError.connection("Password contains a newline, which the client config can't carry.")
        }
        var lines = [
            "[client]",
            "user=\(user)",
            "host=\(host)",
            "port=\(port)",
            "ssl-mode=\(sslMode(for: tlsMode))",
        ]
        if let password { lines.append("password=\(password)") }
        return lines.joined(separator: "\n") + "\n"
    }

    static func sslMode(for mode: TLSMode) -> String {
        switch mode {
        case .disable: "DISABLED"
        case .prefer: "PREFERRED"
        case .require: "REQUIRED"
        case .verifyFull: "VERIFY_IDENTITY"
        }
    }

    /// mysqldump exits 0 but writes nothing when the account lacks privileges on every table; a
    /// zero-byte artifact would otherwise be stored as a valid-looking but useless backup.
    static func ensureDumpNotEmpty(at url: URL, database: String) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        guard size > 0 else {
            throw DatabaseError.connection(
                "mysqldump produced an empty file for \"\(database)\"; the account may lack privileges on its tables."
            )
        }
    }

    /// Write the defaults file created mode 0600 from the start (not chmod-after) so the password is
    /// never briefly world-readable. Caller is responsible for `defer`-deleting the returned URL.
    static func writeDefaultsFile(content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-mysql-\(UUID().uuidString).cnf")
        let created = FileManager.default.createFile(
            atPath: url.path,
            contents: Data(content.utf8),
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw DatabaseError.connection("Couldn't write the temporary database client config.")
        }
        return url
    }
}
