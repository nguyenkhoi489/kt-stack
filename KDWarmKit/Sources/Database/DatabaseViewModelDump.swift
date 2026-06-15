import Foundation

/// Export/import orchestration for the import/export sheet. The heavy lifting (subprocess, cred
/// safety) lives in `DumpService`; here we resolve the password for the active profile, track
/// `dumpStatus`, and refresh the schema after a successful import.
public extension DatabaseViewModel {

    /// True when import/export is available: the `mysqldump`/`mysql` clients drive it, so it's offered
    /// only for MySQL connections (PostgreSQL/SQLite dump support is a separate follow-up) and only when
    /// those on-demand tools are installed.
    var canDump: Bool { selectedProfile?.kind == .mysql && dumpService.isEngineInstalled }

    func clearDumpStatus() { dumpStatus = .idle }

    /// Export the selected database (or a single `table`) to `output`.
    func exportDatabase(to output: URL, table: String? = nil) async {
        guard let profile = selectedProfile, let database = selectedDatabase else { return }
        dumpStatus = .running
        do {
            try await dumpService.export(profile: profile, password: passwordFor(profile),
                                         database: database, table: table, to: output)
            dumpStatus = .done("Exported \(table ?? database) to \(output.lastPathComponent).")
        } catch {
            dumpStatus = .failed(Self.asDatabaseError(error).message)
        }
    }

    /// Import a `.sql` dump into `database` (created if absent). On success, refresh the database list
    /// so the freshly loaded DB appears, and reselect it if it was the active one.
    func importDatabase(into database: String, from input: URL) async {
        guard let profile = selectedProfile else { return }
        // Import is a write/DDL channel (CREATE DATABASE + loading arbitrary SQL through the `mysql`
        // client, which never sets the driver's read-only session flag). Honor the read-only contract
        // the rest of the editor enforces, so a connection marked read-only can't be written to.
        guard !isReadOnlyConnection else {
            dumpStatus = .failed("This connection is read-only; importing is disabled.")
            return
        }
        dumpStatus = .running
        do {
            try await dumpService.importDump(profile: profile, password: passwordFor(profile),
                                             database: database, from: input)
            dumpStatus = .done("Imported \(input.lastPathComponent) into \(database).")
            if let driver, let refreshed = try? await driver.listDatabases() {
                databases = refreshed
            }
            if selectedDatabase == database {
                await select(database: database)
            }
        } catch {
            dumpStatus = .failed(Self.asDatabaseError(error).message)
        }
    }
}
