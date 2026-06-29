import Foundation

public extension DumpService {
    /// `isEngineInstalled` only checks `mysqldump`; both clients must resolve (managed or system) and
    /// be executable before a backup/restore round-trip is offered.
    var requiredBinariesPresent: Bool {
        clientBinary("bin/mysqldump") != nil && clientBinary("bin/mysql") != nil
    }

    func databaseExists(profile: ConnectionProfile, password: String?, database: String) async throws -> Bool {
        try DumpService.validateIdentifier(database, label: "database")
        let mysql = try resolveBinary("bin/mysql")
        let defaults = try DumpService.writeDefaultsFile(
            content: DumpService.defaultsContent(
                user: profile.user, host: profile.host, port: profile.port, password: password,
                tlsMode: profile.tlsMode
            )
        )
        defer { try? FileManager.default.removeItem(at: defaults) }

        let sql = "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '\(database)'"
        let output = try await runCapturing(
            mysql, args: ["--defaults-extra-file=\(defaults.path)", "-N", "-B", "-e", sql]
        )
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func runStatement(profile: ConnectionProfile, password: String?, sql: String) async throws {
        let mysql = try resolveBinary("bin/mysql")
        let defaults = try DumpService.writeDefaultsFile(
            content: DumpService.defaultsContent(
                user: profile.user, host: profile.host, port: profile.port, password: password,
                tlsMode: profile.tlsMode
            )
        )
        defer { try? FileManager.default.removeItem(at: defaults) }
        try await runProcess(
            mysql,
            args: ["--defaults-extra-file=\(defaults.path)", "-e", sql],
            stdin: nil,
            stdout: nil
        )
    }
}
