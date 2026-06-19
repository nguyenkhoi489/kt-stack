import Foundation

public extension DocumentViewModel {

    typealias BackupStatus = DatabaseViewModel.BackupStatus

    var canBackup: Bool {
        guard selectedProfile?.kind == .mongodb else { return false }
        if case .available = BackupProviderFactory.make(for: .mongodb) { return true }
        return false
    }

    var backupUnavailableReason: String? {
        guard let kind = selectedProfile?.kind else { return "Pick a connection first." }
        guard kind == .mongodb else { return "Use the relational track for \(kind.rawValue) backups." }
        switch BackupProviderFactory.make(for: .mongodb) {
        case .available: return nil
        case .unavailable(let reason): return reason
        }
    }

    var canManualImport: Bool { canBackup && !isReadOnlyConnection }

    var canCreateDatabase: Bool { selectedProfile?.kind == .mongodb && !isReadOnlyConnection }

    var manualImportUnavailableReason: String? {
        guard selectedProfile?.kind == .mongodb else { return "Pick a MongoDB connection first." }
        if isReadOnlyConnection { return "This connection is read-only; importing is disabled." }
        return backupUnavailableReason
    }

    func backupDatabase(_ database: String, session: BackupSession) async -> BackupSet? {
        guard let profile = selectedProfile else {
            backupStatus = .failed("Connect to a database before backing up.")
            return nil
        }
        backupStatus = .running("Backing up \(database)…")
        do {
            let set = try await session.create(profile: profile, password: passwordFor(profile),
                                                databases: [database])
            backupStatus = .done("Backed up \(database).")
            return set
        } catch {
            backupStatus = .failed(Self.asDatabaseError(error).message)
            return nil
        }
    }

    func backupAllDatabases(session: BackupSession) async -> BackupSet? {
        guard let profile = selectedProfile, let driver else {
            backupStatus = .failed("Connect to a database before backing up.")
            return nil
        }
        backupStatus = .running("Listing databases…")
        let names: [String]
        do {
            let all = try await driver.listDatabases().map(\.name)
            names = BackupSession.userDatabaseNames(all, for: profile.kind)
        } catch {
            backupStatus = .failed(Self.asDatabaseError(error).message)
            return nil
        }
        guard !names.isEmpty else {
            backupStatus = .failed("No user databases to back up (only system databases were found).")
            return nil
        }
        backupStatus = .running("Backing up \(names.count) databases…")
        do {
            let set = try await session.create(profile: profile, password: passwordFor(profile),
                                                databases: names)
            backupStatus = .done("Backed up \(names.count) databases.")
            return set
        } catch {
            backupStatus = .failed(Self.asDatabaseError(error).message)
            return nil
        }
    }

    func restoreAllDatabases(_ set: BackupSet, session: BackupSession) async -> Bool {
        guard let profile = selectedProfile else { return false }
        guard !isReadOnlyConnection else {
            backupStatus = .failed("This connection is read-only; restore is disabled.")
            return false
        }
        var succeeded = 0
        for database in set.databases {
            backupStatus = .running("Restoring \(database) (\(succeeded + 1)/\(set.databases.count))…")
            do {
                try await session.restore(set: set, database: database, profile: profile,
                                           password: passwordFor(profile), target: .overwrite)
                succeeded += 1
            } catch {
                backupStatus = .failed("Failed restoring \(database): \(Self.asDatabaseError(error).message)")
                return false
            }
        }
        backupStatus = .done("Restored \(succeeded) databases.")
        if let refreshed = try? await driver?.listDatabases() {
            databases = refreshed
        }
        return true
    }

    func restoreBackup(_ set: BackupSet, database: String, target: RestoreTarget,
                       session: BackupSession) async -> Bool {
        guard let profile = selectedProfile else { return false }
        guard !isReadOnlyConnection else {
            backupStatus = .failed("This connection is read-only; restore is disabled.")
            return false
        }
        backupStatus = .running("Restoring \(database)…")
        do {
            try await session.restore(set: set, database: database, profile: profile,
                                       password: passwordFor(profile), target: target)
            backupStatus = .done("Restored \(database).")
            if let refreshed = try? await driver?.listDatabases() {
                databases = refreshed
            }
            return true
        } catch {
            backupStatus = .failed(Self.asDatabaseError(error).message)
            return false
        }
    }

    func deleteBackup(_ set: BackupSet, session: BackupSession) {
        do {
            try session.delete(set)
            backupStatus = .done("Deleted the backup set.")
        } catch {
            backupStatus = .failed(Self.asDatabaseError(error).message)
        }
    }

    func exportBackup(_ set: BackupSet, to destination: URL, session: BackupSession) {
        do {
            try session.exportSet(set, to: destination)
            backupStatus = .done("Exported backup to \(destination.lastPathComponent).")
        } catch {
            backupStatus = .failed(Self.asDatabaseError(error).message)
        }
    }

    func clearBackupStatus() { backupStatus = .idle }

    func targetDatabaseExists(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let driver else { return false }
        let names = (try? await driver.listDatabases().map(\.name)) ?? databases.map(\.name)
        return names.contains(trimmed)
    }

    func failBackupStatus(_ message: String) { backupStatus = .failed(message) }

    func importDatabase(into database: String, from input: URL, replaceExisting: Bool) async {
        guard let profile = selectedProfile else { return }
        guard !isReadOnlyConnection else {
            backupStatus = .failed("This connection is read-only; importing is disabled.")
            return
        }
        backupStatus = .running("Importing \(database)…")
        do {
            try await MongoBackupProvider().restore(profile: profile, password: passwordFor(profile),
                                                    from: input, intoDatabase: database,
                                                    replaceExisting: replaceExisting)
            backupStatus = .done("Imported \(input.lastPathComponent) into \(database).")
            if let refreshed = try? await driver?.listDatabases() {
                databases = refreshed
            }
            await select(database: database)
        } catch {
            backupStatus = .failed(Self.asDatabaseError(error).message)
        }
    }

    @discardableResult
    func createDatabase(named name: String) async -> Bool {
        guard let driver else { return false }
        guard !isReadOnlyConnection else {
            backupStatus = .failed("This connection is read-only; creating databases is disabled.")
            return false
        }
        let database = name.trimmingCharacters(in: .whitespacesAndNewlines)
        backupStatus = .running("Creating \(database)…")
        do {
            try MongoBackupProvider.validateMongoName(database, label: "database")
            try await driver.createCollection(database: database, name: "_ktstack_init")
            backupStatus = .done("Created \(database).")
            if let refreshed = try? await driver.listDatabases() {
                databases = refreshed
            }
            await select(database: database)
            return true
        } catch {
            backupStatus = .failed(Self.asDatabaseError(error).message)
            return false
        }
    }
}
