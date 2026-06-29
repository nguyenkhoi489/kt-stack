import Foundation

/// `pg_dump -Fc` custom-format backup. Restore never runs `--clean` against the live database; it
/// restores into a freshly created temporary database, verifies success, then renames it into place
/// so a mid-restore failure can never destroy the only copy of the target.
public struct PostgresBackupProvider: BackupProvider {
    private let runner: PostgresBackupRunner
    private let dialect = SQLDialect.forKind(.postgres)

    public init() {
        runner = PostgresBackupRunner()
    }

    init(runner: PostgresBackupRunner) {
        self.runner = runner
    }

    public var fileExtension: String {
        "dump"
    }

    public var isAvailable: Bool {
        runner.isAvailable
    }

    public func createDatabase(
        profile: ConnectionProfile,
        password: String?,
        database: String
    ) async throws {
        try DumpService.validateIdentifier(database, label: "database")
        let passwordFile = try runner.writePasswordFile(password)
        defer { if let passwordFile { try? FileManager.default.removeItem(at: passwordFile) } }
        try await createDatabase(database, profile: profile, passwordFile: passwordFile)
    }

    public func databaseExists(
        profile: ConnectionProfile,
        password: String?,
        database: String
    ) async throws -> Bool {
        try DumpService.validateIdentifier(database, label: "database")
        let passwordFile = try runner.writePasswordFile(password)
        defer { if let passwordFile { try? FileManager.default.removeItem(at: passwordFile) } }
        return try await databaseExists(database, profile: profile, passwordFile: passwordFile)
    }

    public func importManual(
        profile: ConnectionProfile,
        password: String?,
        from artifactURL: URL,
        database: String,
        replaceExisting: Bool
    ) async throws {
        try DumpService.validateIdentifier(database, label: "database")
        guard FileManager.default.fileExists(atPath: artifactURL.path) else {
            throw DatabaseError.connection("Import file not found: \(artifactURL.lastPathComponent)")
        }

        let passwordFile = try runner.writePasswordFile(password)
        defer { if let passwordFile { try? FileManager.default.removeItem(at: passwordFile) } }

        if artifactURL.pathExtension.lowercased() == "sql" {
            try await importSQL(
                artifactURL,
                into: database,
                profile: profile,
                passwordFile: passwordFile,
                replaceExisting: replaceExisting
            )
            return
        }

        if replaceExisting {
            try await overwrite(database, from: artifactURL, profile: profile, passwordFile: passwordFile)
        } else {
            if try await databaseExists(database, profile: profile, passwordFile: passwordFile) {
                throw DatabaseError.connection(
                    "A database named \"\(database)\" already exists. Choose another name or overwrite it explicitly."
                )
            }
            try await createDatabase(database, profile: profile, passwordFile: passwordFile)
            do {
                try await restoreArchive(artifactURL, into: database, profile: profile, passwordFile: passwordFile)
            } catch {
                try? await dropDatabase(database, profile: profile, passwordFile: passwordFile)
                throw error
            }
        }
    }

    public func backup(
        profile: ConnectionProfile,
        password: String?,
        database: String,
        to artifactURL: URL
    ) async throws {
        try DumpService.validateIdentifier(database, label: "database")
        let pgDump = try runner.binary("bin/pg_dump")
        let passwordFile = try runner.writePasswordFile(password)
        defer { if let passwordFile { try? FileManager.default.removeItem(at: passwordFile) } }
        do {
            try await runner.run(
                pgDump,
                args: runner.connectionArgs(profile) + ["-Fc", "-d", database, "-f", artifactURL.path],
                passwordFile: passwordFile
            )
        } catch {
            try? FileManager.default.removeItem(at: artifactURL)
            throw error
        }
    }

    public func restore(
        profile: ConnectionProfile,
        password: String?,
        from artifactURL: URL,
        into target: RestoreTarget
    ) async throws {
        let passwordFile = try runner.writePasswordFile(password)
        defer { if let passwordFile { try? FileManager.default.removeItem(at: passwordFile) } }

        switch target {
        case let .newDatabase(name):
            try DumpService.validateIdentifier(name, label: "database")
            if try await databaseExists(name, profile: profile, passwordFile: passwordFile) {
                throw DatabaseError.connection(
                    "A database named \"\(name)\" already exists. Choose another name or overwrite it explicitly."
                )
            }
            try await createDatabase(name, profile: profile, passwordFile: passwordFile)
            do {
                try await restoreArchive(artifactURL, into: name, profile: profile, passwordFile: passwordFile)
            } catch {
                try? await dropDatabase(name, profile: profile, passwordFile: passwordFile)
                throw error
            }
        case .overwrite:
            let database = artifactURL.deletingPathExtension().lastPathComponent
            try DumpService.validateIdentifier(database, label: "database")
            try await overwrite(database, from: artifactURL, profile: profile, passwordFile: passwordFile)
        }
    }

    private func overwrite(
        _ database: String,
        from artifactURL: URL,
        profile: ConnectionProfile,
        passwordFile: URL?
    ) async throws {
        guard try await databaseExists(database, profile: profile, passwordFile: passwordFile) else {
            throw DatabaseError.connection(
                "Cannot overwrite \"\(database)\": the database doesn't exist. "
                    + "Use 'Restore to new database' instead."
            )
        }

        let suffix = String(UUID().uuidString.prefix(8)).lowercased()
        let tempDB = "ktstack_restore_\(suffix)"
        let archivedDB = "\(database)_old_\(suffix)"

        try await createDatabase(tempDB, profile: profile, passwordFile: passwordFile)
        do {
            try await restoreArchive(artifactURL, into: tempDB, profile: profile, passwordFile: passwordFile)
        } catch {
            try? await dropDatabase(tempDB, profile: profile, passwordFile: passwordFile)
            throw error
        }
        do {
            try await terminateConnections(database, profile: profile, passwordFile: passwordFile)
            try await renameDatabase(from: database, to: archivedDB, profile: profile, passwordFile: passwordFile)
            try await renameDatabase(from: tempDB, to: database, profile: profile, passwordFile: passwordFile)
        } catch {
            try? await dropDatabase(tempDB, profile: profile, passwordFile: passwordFile)
            try? await renameDatabase(from: archivedDB, to: database, profile: profile, passwordFile: passwordFile)
            throw DatabaseError.connection(
                "Restore failed and the original \"\(database)\" was preserved: \(Self.message(error))"
            )
        }
        try? await dropDatabase(archivedDB, profile: profile, passwordFile: passwordFile)
    }

    private func restoreArchive(
        _ artifactURL: URL,
        into database: String,
        profile: ConnectionProfile,
        passwordFile: URL?
    ) async throws {
        let pgRestore = try runner.binary("bin/pg_restore")
        try await runner.run(
            pgRestore,
            args: runner.connectionArgs(profile) + ["--no-owner", "--no-acl", "-d", database, artifactURL.path],
            passwordFile: passwordFile
        )
    }

    private func importSQL(
        _ artifactURL: URL,
        into database: String,
        profile: ConnectionProfile,
        passwordFile: URL?,
        replaceExisting: Bool
    ) async throws {
        let existed = try await databaseExists(database, profile: profile, passwordFile: passwordFile)
        if !replaceExisting, existed {
            throw DatabaseError.connection(
                "A database named \"\(database)\" already exists. Choose another name or overwrite it explicitly."
            )
        }
        if !existed {
            try await createDatabase(database, profile: profile, passwordFile: passwordFile)
        }
        let psql = try runner.binary("bin/psql")
        do {
            try await runner.run(
                psql,
                args: runner.connectionArgs(profile)
                    + ["-d", database, "-v", "ON_ERROR_STOP=1", "-f", artifactURL.path],
                passwordFile: passwordFile
            )
        } catch {
            if !existed {
                try? await dropDatabase(database, profile: profile, passwordFile: passwordFile)
            }
            throw error
        }
    }

    private func createDatabase(_ name: String, profile: ConnectionProfile, passwordFile: URL?) async throws {
        let createdb = try runner.binary("bin/createdb")
        try await runner.run(
            createdb,
            args: runner.connectionArgs(profile) + [name],
            passwordFile: passwordFile
        )
    }

    private func dropDatabase(_ name: String, profile: ConnectionProfile, passwordFile: URL?) async throws {
        let dropdb = try runner.binary("bin/dropdb")
        try await runner.run(
            dropdb,
            args: runner.connectionArgs(profile) + ["--if-exists", name],
            passwordFile: passwordFile
        )
    }

    private func databaseExists(_ name: String, profile: ConnectionProfile, passwordFile: URL?) async throws -> Bool {
        let psql = try runner.binary("bin/psql")
        let escaped = name.replacingOccurrences(of: "'", with: "''")
        let output = try await runner.run(
            psql,
            args: runner.connectionArgs(profile)
                + ["-d", "postgres", "-tAc", "SELECT 1 FROM pg_database WHERE datname = '\(escaped)'"],
            passwordFile: passwordFile
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private func terminateConnections(_ name: String, profile: ConnectionProfile, passwordFile: URL?) async throws {
        let psql = try runner.binary("bin/psql")
        let escaped = name.replacingOccurrences(of: "'", with: "''")
        let sql = "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
            + "WHERE datname = '\(escaped)' AND pid <> pg_backend_pid()"
        try await runner.run(
            psql,
            args: runner.connectionArgs(profile) + ["-d", "postgres", "-c", sql],
            passwordFile: passwordFile
        )
    }

    private func renameDatabase(
        from: String,
        to: String,
        profile: ConnectionProfile,
        passwordFile: URL?
    ) async throws {
        let psql = try runner.binary("bin/psql")
        let sql = try "ALTER DATABASE \(dialect.quoteIdent(from)) RENAME TO \(dialect.quoteIdent(to))"
        try await runner.run(
            psql,
            args: runner.connectionArgs(profile) + ["-d", "postgres", "-c", sql],
            passwordFile: passwordFile
        )
    }

    private static func message(_ error: Error) -> String {
        (error as? DatabaseError)?.message ?? error.localizedDescription
    }
}
