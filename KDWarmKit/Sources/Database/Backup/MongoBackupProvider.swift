import Foundation

/// Backup/restore via `mongodump`/`mongorestore`. Per backup set the artifact is a directory of BSON
/// files (one subdir per DB), not a single file. Passwords ride a `--config` YAML written at 0o600
/// and `defer`-deleted; argv only carries the non-secret `--host/--port/--username/--authenticationDatabase`.
public struct MongoBackupProvider: BackupProvider {
    private let catalog: MongoToolsCatalog

    public init(paths: AppSupportPaths = AppSupportPaths()) {
        self.catalog = MongoToolsCatalog(paths: paths)
    }

    public var fileExtension: String { "" }
    public var isAvailable: Bool { catalog.isInstalled }

    public func backup(profile: ConnectionProfile, password: String?,
                       database: String, to artifactURL: URL) async throws {
        try Self.validateMongoName(database, label: "database")
        let mongodump = try resolve("bin/mongodump")
        try FileManager.default.createDirectory(at: artifactURL, withIntermediateDirectories: true)
        let config = try writeConfigFile(password)
        defer { if let config { try? FileManager.default.removeItem(at: config) } }
        do {
            try await run(mongodump,
                          args: try connectionArgs(profile, config: config) + ["--db", database,
                                                                                "--out", artifactURL.path])
        } catch {
            try? FileManager.default.removeItem(at: artifactURL)
            throw error
        }
    }

    public func restore(profile: ConnectionProfile, password: String?,
                        from artifactURL: URL, into target: RestoreTarget) async throws {
        try requireDirectory(artifactURL)
        let database = artifactURL.lastPathComponent
        try Self.validateMongoName(database, label: "database")

        let mongorestore = try resolve("bin/mongorestore")
        let config = try writeConfigFile(password)
        defer { if let config { try? FileManager.default.removeItem(at: config) } }

        switch target {
        case .newDatabase(let name):
            try Self.validateMongoName(name, label: "database")
            try await run(mongorestore,
                          args: try connectionArgs(profile, config: config)
                              + ["--nsFrom", "\(database).*", "--nsTo", "\(name).*",
                                 artifactURL.path])
        case .overwrite:
            try await overwrite(database: database, from: artifactURL,
                                profile: profile, password: password,
                                mongorestore: mongorestore, config: config)
        }
    }

    private func overwrite(database: String, from artifactURL: URL,
                           profile: ConnectionProfile, password: String?,
                           mongorestore: URL, config: URL?) async throws {
        let mongodump = try resolve("bin/mongodump")
        let safetyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kdwarm-mongo-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: safetyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: safetyDir) }

        try await run(mongodump,
                      args: try connectionArgs(profile, config: config) + ["--db", database,
                                                                            "--out", safetyDir.path])
        do {
            try await run(mongorestore,
                          args: try connectionArgs(profile, config: config)
                              + ["--drop", "--nsFrom", "\(database).*", "--nsTo", "\(database).*",
                                 artifactURL.path])
        } catch {
            // Rollback restores the safety dump but `--drop` only removes collections that EXIST in
            // the safety set. Any collection the failing artifact added before the failure survives
            // the rollback (mixed state). Surface this in the error so the user inspects.
            let safetySource = safetyDir.appendingPathComponent(database)
            if FileManager.default.fileExists(atPath: safetySource.path) {
                try? await run(mongorestore,
                               args: try connectionArgs(profile, config: config)
                                   + ["--drop", "--nsFrom", "\(database).*", "--nsTo", "\(database).*",
                                      safetySource.path])
            }
            throw DatabaseError.connection(
                "Restore failed and \"\(database)\" was rolled back to the safety snapshot. "
                + "Any collection added by the failing restore before failure may still be present "
                + "— inspect before retrying. Cause: \(Self.message(error))")
        }
    }

    // MARK: - Tooling

    private func resolve(_ relPath: String) throws -> URL {
        guard let url = catalog.binary(relPath) else {
            throw DatabaseError.engineNotInstalled(kind: "MongoDB database tools")
        }
        return url
    }

    /// Host and user reach mongodump/mongorestore argv; reject a host like `-XfromSomewhere` or a
    /// user starting with `-` that would smuggle an option past the parser. Mirrors the Postgres
    /// runner's contract.
    private func connectionArgs(_ profile: ConnectionProfile, config: URL?) throws -> [String] {
        try DumpService.validateHost(profile.host)
        if !profile.user.isEmpty {
            try DumpService.validateIdentifier(profile.user, label: "user", maxLength: 255)
        }
        var args = ["--host", profile.host, "--port", String(profile.port)]
        if !profile.user.isEmpty {
            args.append(contentsOf: ["--username", profile.user, "--authenticationDatabase", "admin"])
        }
        if let config {
            args.append(contentsOf: ["--config", config.path])
        }
        return args
    }

    private func writeConfigFile(_ password: String?) throws -> URL? {
        guard let password, !password.isEmpty else { return nil }
        for scalar in password.unicodeScalars {
            // Control chars (incl. NUL/newline/tab) would corrupt the single-line YAML scalar.
            if scalar.value < 0x20 || scalar.value == 0x7f {
                throw DatabaseError.connection("Password contains a character the MongoDB tools config can't carry.")
            }
        }
        let escaped = password.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let yaml = "password: \"\(escaped)\"\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kdwarm-mongo-\(UUID().uuidString).yaml")
        let created = FileManager.default.createFile(
            atPath: url.path,
            contents: Data(yaml.utf8),
            attributes: [.posixPermissions: 0o600])
        guard created else {
            throw DatabaseError.connection("Couldn't write the temporary MongoDB client config.")
        }
        return url
    }

    private func requireDirectory(_ url: URL) throws {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard exists, isDir.boolValue else {
            throw DatabaseError.connection("MongoDB backup artifact must be a directory.")
        }
    }

    private func run(_ executable: URL, args: [String]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = executable
                proc.arguments = args
                proc.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
                let errPipe = Pipe()
                proc.standardError = errPipe
                proc.standardOutput = FileHandle.nullDevice
                proc.standardInput = FileHandle.nullDevice
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

    private static func message(_ error: Error) -> String {
        (error as? DatabaseError)?.message ?? error.localizedDescription
    }

    /// MongoDB DB names also can't contain `/\. "$` and we additionally reject `*?[]` because
    /// `mongorestore --nsFrom` treats them as glob meta. A name like `app*` would otherwise expand
    /// the source namespace and restore unintended collections.
    static func validateMongoName(_ value: String, label: String) throws {
        try DumpService.validateIdentifier(value, label: label)
        let banned: Set<Character> = ["*", "?", "[", "]", "$", " ", "."]
        for char in value where banned.contains(char) {
            throw DatabaseError.connection("Illegal character in MongoDB \(label) name: '\(char)'")
        }
    }
}
