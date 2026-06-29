import Foundation

/// Export/import orchestration for the import/export sheet. The heavy lifting (subprocess, cred
/// safety) lives in `DumpService`; here we resolve the password for the active profile, track
/// `dumpStatus`, and refresh the schema after a successful import.
public extension DatabaseViewModel {
    var canDump: Bool {
        selectedProfile?.kind == .mysql && dumpService.isEngineInstalled
    }

    var canManualImport: Bool {
        guard let kind = selectedProfile?.kind else { return false }
        switch kind {
        case .mysql:
            return dumpService.isEngineInstalled
        case .postgres, .sqlite:
            if case .available = BackupProviderFactory.make(for: kind) { return true }
            return false
        case .mongodb:
            return false
        }
    }

    var canCreateDatabase: Bool {
        guard let kind = selectedProfile?.kind, !isReadOnlyConnection else { return false }
        switch kind {
        case .mysql:
            return dumpService.isEngineInstalled
        case .postgres:
            if case .available = BackupProviderFactory.make(for: .postgres) { return true }
            return false
        case .sqlite, .mongodb:
            return false
        }
    }

    var importUnavailableReason: String? {
        guard let kind = selectedProfile?.kind else { return "Pick a connection first." }
        switch kind {
        case .mysql:
            return dumpService.isEngineInstalled ? nil : "Install the MySQL engine to enable .sql import."
        case .postgres, .sqlite:
            switch BackupProviderFactory.make(for: kind) {
            case .available: return nil
            case let .unavailable(reason): return reason
            }
        case .mongodb:
            return "Use the MongoDB document track for dump folders."
        }
    }

    func clearDumpStatus() {
        dumpStatus = .idle
    }

    func targetDatabaseExists(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile = selectedProfile, !trimmed.isEmpty else { return false }
        switch profile.kind {
        case .mysql:
            guard let driver else { return false }
            let names = await (try? driver.listDatabases().map(\.name)) ?? []
            return names.contains(trimmed)
        case .postgres:
            return await (try? PostgresBackupProvider().databaseExists(
                profile: profile, password: passwordFor(profile), database: trimmed
            )) ?? false
        case .sqlite, .mongodb:
            return false
        }
    }

    func importFullDump(from input: URL) async {
        guard let profile = selectedProfile, profile.kind == .mysql else { return }
        guard !isReadOnlyConnection else {
            dumpStatus = .failed("This connection is read-only; importing is disabled.")
            return
        }
        dumpStatus = .running
        do {
            try await dumpService.importFullDump(profile: profile, password: passwordFor(profile), from: input)
            dumpStatus = .done("Imported all databases from \(input.lastPathComponent).")
            if let driver, let refreshed = try? await driver.listDatabases() {
                databases = refreshed
            }
        } catch {
            dumpStatus = .failed(Self.asDatabaseError(error).message)
        }
    }

    func importSQLite(from input: URL, into target: RestoreTarget) async {
        guard let profile = selectedProfile, profile.kind == .sqlite else { return }
        guard !isReadOnlyConnection else {
            dumpStatus = .failed("This connection is read-only; importing is disabled.")
            return
        }
        dumpStatus = .running
        do {
            try await SQLiteBackupProvider().restore(
                profile: profile,
                password: passwordFor(profile),
                from: input,
                into: target
            )
            switch target {
            case .overwrite:
                let name = URL(fileURLWithPath: profile.filePath ?? profile.database).lastPathComponent
                dumpStatus = .done("Imported \(input.lastPathComponent) into \(name).")
                if selectedDatabase != nil { await select(database: SQLiteDriver.mainDatabase) }
            case let .newDatabase(path):
                dumpStatus = .done("Saved \(input.lastPathComponent) to \(URL(fileURLWithPath: path).lastPathComponent).")
            }
        } catch {
            dumpStatus = .failed(Self.asDatabaseError(error).message)
        }
    }

    func exportResultCSV(to output: URL) {
        guard let result else { return }
        exportResultCSV(result, to: output)
    }

    func exportResultCSV(_ result: QueryResult, to output: URL) {
        do {
            try Data(QueryResultTextSerializer.csv(result).utf8).write(to: output, options: .atomic)
            dumpStatus = .done("Exported \(result.rowCount) rows to \(output.lastPathComponent).")
        } catch {
            dumpStatus = .failed(Self.asDatabaseError(error).message)
        }
    }

    /// Export the selected database (or a single `table`) to `output`.
    func exportDatabase(to output: URL, table: String? = nil) async {
        guard let profile = selectedProfile, let database = selectedDatabase else { return }
        dumpStatus = .running
        do {
            try await dumpService.export(
                profile: profile,
                password: passwordFor(profile),
                database: database,
                table: table,
                to: output
            )
            dumpStatus = .done("Exported \(table ?? database) to \(output.lastPathComponent).")
        } catch {
            dumpStatus = .failed(Self.asDatabaseError(error).message)
        }
    }

    /// Import a `.sql` dump into `database` (created if absent). On success, refresh the database list
    /// so the freshly loaded DB appears, and reselect it if it was the active one.
    func importDatabase(into database: String, from input: URL) async {
        await importDatabase(into: database, from: input, replaceExisting: false)
    }

    func importDatabase(into database: String, from input: URL, replaceExisting: Bool) async {
        guard let profile = selectedProfile else { return }
        guard !isReadOnlyConnection else {
            dumpStatus = .failed("This connection is read-only; importing is disabled.")
            return
        }
        dumpStatus = .running
        do {
            switch profile.kind {
            case .mysql:
                try await dumpService.importDump(
                    profile: profile,
                    password: passwordFor(profile),
                    database: database,
                    from: input
                )
            case .postgres:
                try await PostgresBackupProvider().importManual(
                    profile: profile, password: passwordFor(profile), from: input,
                    database: database, replaceExisting: replaceExisting
                )
            case .sqlite:
                try await SQLiteBackupProvider().restore(
                    profile: profile,
                    password: passwordFor(profile),
                    from: input,
                    into: .overwrite
                )
            case .mongodb:
                throw DatabaseError.connection("Use the MongoDB document track for dump folder import.")
            }
            let target = profile.kind == .sqlite
                ? URL(fileURLWithPath: profile.filePath ?? profile.database).lastPathComponent
                : database
            dumpStatus = .done("Imported \(input.lastPathComponent) into \(target).")
            if let driver, let refreshed = try? await driver.listDatabases() {
                databases = refreshed
            }
            if profile.kind != .sqlite, databases.contains(where: { $0.name == database }) {
                await select(database: database)
            }
        } catch {
            dumpStatus = .failed(Self.asDatabaseError(error).message)
        }
    }

    @discardableResult
    func createDatabase(named name: String) async -> Bool {
        guard let profile = selectedProfile else { return false }
        guard !isReadOnlyConnection else {
            dumpStatus = .failed("This connection is read-only; creating databases is disabled.")
            return false
        }
        let database = name.trimmingCharacters(in: .whitespacesAndNewlines)
        dumpStatus = .running
        do {
            switch profile.kind {
            case .mysql:
                try await dumpService.createDatabase(
                    profile: profile,
                    password: passwordFor(profile),
                    database: database
                )
            case .postgres:
                try await PostgresBackupProvider().createDatabase(
                    profile: profile, password: passwordFor(profile), database: database
                )
            case .sqlite, .mongodb:
                throw DatabaseError.connection("Create Database isn't available for \(profile.kind.rawValue).")
            }
            dumpStatus = .done("Created \(database).")
            if let driver, let refreshed = try? await driver.listDatabases() {
                databases = refreshed
            }
            await select(database: database)
            return true
        } catch {
            dumpStatus = .failed(Self.asDatabaseError(error).message)
            return false
        }
    }
}
