import Foundation

/// Adapts the existing `DumpService` to the engine-agnostic `BackupProvider`. MySQL has no atomic
/// `RENAME DATABASE`, so `.overwrite` uses the documented fallback to the temp-swap invariant: a
/// verified pre-restore safety dump with auto-rollback, never destroying the only copy until the new
/// restore has loaded.
public struct MySQLBackupProvider: BackupProvider {
    private let dumpService: DumpService

    public init(dumpService: DumpService = DumpService()) {
        self.dumpService = dumpService
    }

    public var fileExtension: String { "sql" }
    public var isAvailable: Bool { dumpService.requiredBinariesPresent }

    public func backup(profile: ConnectionProfile, password: String?,
                       database: String, to artifactURL: URL) async throws {
        try await dumpService.export(profile: profile, password: password,
                                     database: database, table: nil, to: artifactURL)
    }

    public func restore(profile: ConnectionProfile, password: String?,
                        from artifactURL: URL, into target: RestoreTarget) async throws {
        switch target {
        case .newDatabase(let name):
            try DumpService.validateIdentifier(name, label: "database")
            if try await dumpService.databaseExists(profile: profile, password: password, database: name) {
                throw DatabaseError.connection(
                    "A database named \"\(name)\" already exists. Choose another name or overwrite it explicitly.")
            }
            do {
                try await dumpService.importDump(profile: profile, password: password,
                                                 database: name, from: artifactURL)
            } catch {
                try? await dumpService.runStatement(
                    profile: profile, password: password,
                    sql: "DROP DATABASE IF EXISTS \(try SQLDialect.forKind(.mysql).quoteIdent(name))")
                throw error
            }
        case .overwrite:
            let database = artifactURL.deletingPathExtension().lastPathComponent
            try await overwrite(profile: profile, password: password, database: database, from: artifactURL)
        }
    }

    private func overwrite(profile: ConnectionProfile, password: String?,
                           database: String, from artifactURL: URL) async throws {
        try DumpService.validateIdentifier(database, label: "database")
        let quoted = try SQLDialect.forKind(.mysql).quoteIdent(database)

        let safety = FileManager.default.temporaryDirectory
            .appendingPathComponent("kdwarm-mysql-safety-\(UUID().uuidString).sql")
        defer { try? FileManager.default.removeItem(at: safety) }
        try await dumpService.export(profile: profile, password: password,
                                     database: database, table: nil, to: safety)
        // mysqldump exits 0 but writes nothing when (e.g.) the role lacks privileges on every
        // table. A zero-byte safety file would silently make rollback restore an empty DB.
        let safetySize = (try? FileManager.default.attributesOfItem(atPath: safety.path)[.size] as? Int64) ?? 0
        guard safetySize > 0 else {
            throw DatabaseError.connection(
                "Pre-restore safety dump for \"\(database)\" is empty; aborting before any destructive step.")
        }

        do {
            try await dumpService.runStatement(profile: profile, password: password,
                                               sql: "DROP DATABASE IF EXISTS \(quoted)")
            try await dumpService.importDump(profile: profile, password: password,
                                             database: database, from: artifactURL)
        } catch {
            try? await dumpService.runStatement(profile: profile, password: password,
                                                sql: "DROP DATABASE IF EXISTS \(quoted)")
            try? await dumpService.importDump(profile: profile, password: password,
                                              database: database, from: safety)
            throw DatabaseError.connection(
                "Restore failed and the original \"\(database)\" was rolled back: \(Self.message(error))")
        }
    }

    private static func message(_ error: Error) -> String {
        (error as? DatabaseError)?.message ?? error.localizedDescription
    }
}
