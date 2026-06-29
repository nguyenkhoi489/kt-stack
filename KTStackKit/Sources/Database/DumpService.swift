import Foundation

/// Export/import MySQL databases via the `mysqldump`/`mysql` clients. Clients resolve from the managed
/// engine first, then from system locations (Homebrew/PATH), so connections to external hosts work
/// even when the managed engine was never installed. The Process work runs off the main thread so the
/// UI never blocks. Security: see `DumpServiceValidation` — creds via a 0600 defaults file, identifiers
/// allowlist-validated, user values passed after a `--` argv terminator.
public struct DumpService: Sendable {
    let catalog: ServiceBinaryCatalog
    let systemToolSearchPaths: [URL]

    public init(
        catalog: ServiceBinaryCatalog = ServiceBinaryCatalog(paths: AppSupportPaths()),
        systemToolSearchPaths: [URL] = DumpService.defaultSystemToolSearchPaths()
    ) {
        self.catalog = catalog
        self.systemToolSearchPaths = systemToolSearchPaths
    }

    public static func defaultSystemToolSearchPaths() -> [URL] {
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs += path.split(separator: ":").map(String.init)
        }
        var seen = Set<String>()
        return dirs.filter { seen.insert($0).inserted }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// True when `mysqldump` resolves (managed or system); the UI disables import/export otherwise.
    public var isEngineInstalled: Bool {
        clientBinary("bin/mysqldump") != nil
    }

    /// Resolve a client binary: the managed engine catalog first, then system search paths. Only an
    /// executable file qualifies, so a catalog path for a binary that isn't actually present is skipped.
    func clientBinary(_ relPath: String) -> URL? {
        let fm = FileManager.default
        if let managed = catalog.binary(.mysql, relPath), fm.isExecutableFile(atPath: managed.path) {
            return managed
        }
        let tool = (relPath as NSString).lastPathComponent
        for dir in systemToolSearchPaths {
            let candidate = dir.appendingPathComponent(tool)
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Dump a whole database (or a single `table`) to `output` as `.sql`. mysqldump writes to stdout,
    /// which we redirect to the file handle.
    public func export(
        profile: ConnectionProfile,
        password: String?,
        database: String,
        table: String?,
        to output: URL
    ) async throws {
        let dump = try resolveBinary("bin/mysqldump")
        try DumpService.validateIdentifier(database, label: "database")
        if let table { try DumpService.validateIdentifier(table, label: "table") }

        let defaults = try DumpService.writeDefaultsFile(
            content: DumpService.defaultsContent(
                user: profile.user, host: profile.host, port: profile.port, password: password,
                tlsMode: profile.tlsMode
            )
        )
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
            try outHandle.close()
            try DumpService.ensureDumpNotEmpty(at: output, database: database)
        } catch {
            // A failed or empty dump may have left partial/zero SQL; remove it so it can't be
            // mistaken for a valid dump.
            try? outHandle.close()
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    /// Load a `.sql` dump into `database`, creating it first (import-into-new default). A killed import
    /// into a freshly created DB can't corrupt unrelated data. Replacing an existing DB is the UI's
    /// explicit-confirm decision; this method just runs the load.
    public func importDump(
        profile: ConnectionProfile,
        password: String?,
        database: String,
        from input: URL
    ) async throws {
        let mysql = try resolveBinary("bin/mysql")
        try DumpService.validateIdentifier(database, label: "database")
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw DatabaseError.connection("Dump file not found: \(input.lastPathComponent)")
        }

        let defaults = try DumpService.writeDefaultsFile(
            content: DumpService.defaultsContent(
                user: profile.user, host: profile.host, port: profile.port, password: password,
                tlsMode: profile.tlsMode
            )
        )
        defer { try? FileManager.default.removeItem(at: defaults) }

        // Create the target DB up front. The name is validated above and backtick-quoted; the SQL
        // rides in argv (visible to `ps`) but carries no secret.
        let quoted = try SQLDialect.forKind(.mysql).quoteIdent(database)
        try await runProcess(
            mysql,
            args: [
                "--defaults-extra-file=\(defaults.path)",
                "-e",
                "CREATE DATABASE IF NOT EXISTS \(quoted)",
            ],
            stdin: nil,
            stdout: nil
        )

        guard let inHandle = try? FileHandle(forReadingFrom: input) else {
            throw DatabaseError.connection("Couldn't open the dump file for reading.")
        }
        defer { try? inHandle.close() }
        try await runProcess(
            mysql,
            args: ["--defaults-extra-file=\(defaults.path)", "--", database],
            stdin: inHandle,
            stdout: nil
        )
    }

    public func importFullDump(profile: ConnectionProfile, password: String?, from input: URL) async throws {
        let mysql = try resolveBinary("bin/mysql")
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw DatabaseError.connection("Dump file not found: \(input.lastPathComponent)")
        }

        let defaults = try DumpService.writeDefaultsFile(
            content: DumpService.defaultsContent(
                user: profile.user, host: profile.host, port: profile.port, password: password,
                tlsMode: profile.tlsMode
            )
        )
        defer { try? FileManager.default.removeItem(at: defaults) }

        guard let inHandle = try? FileHandle(forReadingFrom: input) else {
            throw DatabaseError.connection("Couldn't open the dump file for reading.")
        }
        defer { try? inHandle.close() }
        try await runProcess(
            mysql,
            args: ["--defaults-extra-file=\(defaults.path)"],
            stdin: inHandle,
            stdout: nil
        )
    }

    public func createDatabase(
        profile: ConnectionProfile,
        password: String?,
        database: String
    ) async throws {
        let mysql = try resolveBinary("bin/mysql")
        try DumpService.validateIdentifier(database, label: "database")

        let defaults = try DumpService.writeDefaultsFile(
            content: DumpService.defaultsContent(
                user: profile.user, host: profile.host, port: profile.port, password: password,
                tlsMode: profile.tlsMode
            )
        )
        defer { try? FileManager.default.removeItem(at: defaults) }

        let quoted = try SQLDialect.forKind(.mysql).quoteIdent(database)
        try await runProcess(
            mysql,
            args: [
                "--defaults-extra-file=\(defaults.path)",
                "-e",
                "CREATE DATABASE \(quoted)",
            ],
            stdin: nil,
            stdout: nil
        )
    }

    func resolveBinary(_ relPath: String) throws -> URL {
        guard let url = clientBinary(relPath) else {
            throw DatabaseError.engineNotInstalled(kind: "MySQL")
        }
        return url
    }

    /// Run the client off the main thread (continuation hops to a background queue), draining stderr
    /// for the error message. A non-zero exit surfaces stderr as a connection error.
    func runProcess(
        _ executable: URL,
        args: [String],
        stdin: FileHandle?,
        stdout: FileHandle?
    ) async throws {
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
                        "Couldn't launch \(executable.lastPathComponent): \(error.localizedDescription)"
                    ))
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
                        "\(executable.lastPathComponent) failed (exit \(proc.terminationStatus)): \(message)"
                    ))
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
                        "Couldn't launch \(executable.lastPathComponent): \(error.localizedDescription)"
                    ))
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
                        "\(executable.lastPathComponent) failed (exit \(proc.terminationStatus)): \(message)"
                    ))
                }
            }
        }
    }
}
