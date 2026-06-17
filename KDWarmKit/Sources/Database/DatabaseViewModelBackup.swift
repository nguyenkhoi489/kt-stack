import Foundation

public extension DatabaseViewModel {

    enum BackupStatus: Equatable {
        case idle
        case running(String)
        case done(String)
        case failed(String)
    }

    var canBackup: Bool {
        guard let kind = selectedProfile?.kind, kind != .mongodb else { return false }
        if case .available = BackupProviderFactory.make(for: kind) { return true }
        return false
    }

    /// Reason the backup action is disabled, surfaced as inline UI guidance. Returns nil when
    /// backup is offered for the active connection.
    var backupUnavailableReason: String? {
        guard let kind = selectedProfile?.kind else { return "Pick a connection first." }
        if kind == .mongodb { return "Use the document track for MongoDB backups." }
        switch BackupProviderFactory.make(for: kind) {
        case .available: return nil
        case .unavailable(let reason): return reason
        }
    }

    func backupDatabase(_ database: String, session: BackupSession) async -> BackupSet? {
        guard let profile = selectedProfile else { return nil }
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
        guard let profile = selectedProfile, let driver else { return nil }
        backupStatus = .running("Listing databases…")
        let dbs: [String]
        do {
            dbs = try await driver.listDatabases().map(\.name)
        } catch {
            backupStatus = .failed(Self.asDatabaseError(error).message)
            return nil
        }
        guard !dbs.isEmpty else {
            backupStatus = .failed("No databases to back up.")
            return nil
        }
        backupStatus = .running("Backing up \(dbs.count) databases…")
        do {
            let set = try await session.create(profile: profile, password: passwordFor(profile),
                                                databases: dbs)
            backupStatus = .done("Backed up \(dbs.count) databases.")
            return set
        } catch {
            backupStatus = .failed(Self.asDatabaseError(error).message)
            return nil
        }
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

    func failBackupStatus(_ message: String) { backupStatus = .failed(message) }
}
