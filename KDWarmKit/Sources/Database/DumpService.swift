import Foundation

/// Export/import MySQL databases via the on-demand `mysqldump`/`mysql` clients (resolved through the
/// installed managed engine, so external hosts use those binaries too). The Process work runs off the
/// main thread so the UI never blocks. Security: see `DumpServiceValidation` — creds via a 0600
/// defaults file, identifiers allowlist-validated, user values passed after a `--` argv terminator.
public struct DumpService: Sendable {
    let catalog: ServiceBinaryCatalog

    public init(catalog: ServiceBinaryCatalog = ServiceBinaryCatalog(paths: AppSupportPaths())) {
        self.catalog = catalog
    }

    /// True when the dump tools are available; the UI disables import/export and explains otherwise.
    public var isEngineInstalled: Bool { catalog.binary(.mysql, "bin/mysqldump") != nil }

    func catalogBinary(_ relPath: String) -> URL? { catalog.binary(.mysql, relPath) }

    // MARK: - Export

    /// Dump a whole database (or a single `table`) to `output` as `.sql`. mysqldump writes to stdout,
    /// which we redirect to the file handle.
    public func export(profile: ConnectionProfile, password: String?,
                       database: String, table: String?, to output: URL) async throws {
        let dump = try resolveBinary("bin/mysqldump")
        try DumpService.validateIdentifier(database, label: "database")
        if let table { try DumpService.validateIdentifier(table, label: "table") }

        let defaults = try DumpService.writeDefaultsFile(
            content: try DumpService.defaultsContent(
                user: profile.user, host: profile.host, port: profile.port, password: password))
        defer { try? FileManager.default.removeItem(at: defaults) }

        FileManager.default.createFile(atPath: output.path, contents: nil)
        guard let outHandle = try? FileHandle(forWritingTo: output) else {
            throw DatabaseError.connection("Couldn't open the export file for writing.")
        }
        defer { try? outHandle.close() }

        var args = ["--defaults-extra-file=\(defaults.path)", "--single-transaction", "--", database]
        if let table { args.append(table) }
        do {
            try await runProcess(dump, args: args, stdin: nil, stdout: outHandle)
        } catch {
            // A failed dump may have written partial SQL; remove it so a truncated file can't be
            // mistaken for a valid dump.
            try? outHandle.close()
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    // MARK: - Import

    /// Load a `.sql` dump into `database`, creating it first (import-into-new default). A killed import
    /// into a freshly created DB can't corrupt unrelated data. Replacing an existing DB is the UI's
    /// explicit-confirm decision; this method just runs the load.
    public func importDump(profile: ConnectionProfile, password: String?,
                           database: String, from input: URL) async throws {
        let mysql = try resolveBinary("bin/mysql")
        try DumpService.validateIdentifier(database, label: "database")
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw DatabaseError.connection("Dump file not found: \(input.lastPathComponent)")
        }

        let defaults = try DumpService.writeDefaultsFile(
            content: try DumpService.defaultsContent(
                user: profile.user, host: profile.host, port: profile.port, password: password))
        defer { try? FileManager.default.removeItem(at: defaults) }

        // Create the target DB up front. The name is validated above and backtick-quoted; the SQL
        // rides in argv (visible to `ps`) but carries no secret.
        let quoted = try SQLDialect.forKind(.mysql).quoteIdent(database)
        try await runProcess(mysql,
                      args: ["--defaults-extra-file=\(defaults.path)", "-e",
                             "CREATE DATABASE IF NOT EXISTS \(quoted)"],
                      stdin: nil, stdout: nil)

        guard let inHandle = try? FileHandle(forReadingFrom: input) else {
            throw DatabaseError.connection("Couldn't open the dump file for reading.")
        }
        defer { try? inHandle.close() }
        try await runProcess(mysql,
                      args: ["--defaults-extra-file=\(defaults.path)", "--", database],
                      stdin: inHandle, stdout: nil)
    }

    // MARK: - Process

    func resolveBinary(_ relPath: String) throws -> URL {
        guard let url = catalog.binary(.mysql, relPath) else {
            throw DatabaseError.engineNotInstalled(kind: "MySQL")
        }
        return url
    }

    /// Run the client off the main thread (continuation hops to a background queue), draining stderr
    /// for the error message. A non-zero exit surfaces stderr as a connection error.
    func runProcess(_ executable: URL, args: [String],
                    stdin: FileHandle?, stdout: FileHandle?) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = executable
                proc.arguments = args
                proc.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
                let errPipe = Pipe()
                proc.standardError = errPipe
                proc.standardInput = stdin ?? FileHandle.nullDevice
                proc.standardOutput = stdout ?? FileHandle.nullDevice
                do {
                    try proc.run()
                } catch {
                    cont.resume(throwing: DatabaseError.connection(
                        "Couldn't launch \(executable.lastPathComponent): \(error.localizedDescription)"))
                    return
                }
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    let message = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    cont.resume(throwing: DatabaseError.connection(
                        "\(executable.lastPathComponent) failed (exit \(proc.terminationStatus)): \(message)"))
                }
            }
        }
    }

    func runCapturing(_ executable: URL, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = executable
                proc.arguments = args
                proc.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                proc.standardInput = FileHandle.nullDevice
                do {
                    try proc.run()
                } catch {
                    cont.resume(throwing: DatabaseError.connection(
                        "Couldn't launch \(executable.lastPathComponent): \(error.localizedDescription)"))
                    return
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    cont.resume(returning: String(data: outData, encoding: .utf8) ?? "")
                } else {
                    let message = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    cont.resume(throwing: DatabaseError.connection(
                        "\(executable.lastPathComponent) failed (exit \(proc.terminationStatus)): \(message)"))
                }
            }
        }
    }
}
