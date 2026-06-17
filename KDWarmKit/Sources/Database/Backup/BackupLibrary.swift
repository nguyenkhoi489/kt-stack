import Foundation

public struct BackupLibrary: Sendable {
    private let paths: AppSupportPaths
    private let fileManager: FileManager

    public init(paths: AppSupportPaths = AppSupportPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    // MARK: - Reading

    public func list() -> [BackupSet] {
        reconcileManifest().sorted { $0.createdAt > $1.createdAt }
    }

    public func directory(for set: BackupSet) -> URL {
        paths.backupSetDir(set.id)
    }

    public func size(of set: BackupSet) -> Int64 {
        Self.directorySize(paths.backupSetDir(set.id), fileManager: fileManager)
    }

    // MARK: - Create

    public func create(kind: DatabaseKind, profile: ConnectionProfile, databases: [String],
                       using provider: BackupProvider, password: String?,
                       engineVersion: String? = nil) async throws -> BackupSet {
        guard !databases.isEmpty else {
            throw DatabaseError.connection("No databases selected to back up.")
        }
        try fileManager.createDirectory(at: paths.backups, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])

        let id = UUID()
        let setDir = paths.backupSetDir(id)
        try fileManager.createDirectory(at: setDir, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        do {
            for database in databases {
                let artifact = try Self.safeArtifactURL(
                    database: database, fileExtension: provider.fileExtension, in: setDir)
                try await provider.backup(profile: profile, password: password,
                                          database: database, to: artifact)
            }
            let set = BackupSet(
                id: id, kind: kind, engineVersion: engineVersion,
                profileName: profile.name, host: profile.host, databases: databases,
                createdAt: Date(),
                sizeBytes: Self.directorySize(setDir, fileManager: fileManager))
            try writeMeta(set, in: setDir)
            var manifest = reconcileManifest()
            manifest.removeAll { $0.id == id }
            manifest.append(set)
            try commitManifest(manifest)
            return set
        } catch {
            try? fileManager.removeItem(at: setDir)
            throw error
        }
    }

    // MARK: - Delete

    public func delete(_ set: BackupSet) throws {
        let dir = paths.backupSetDir(set.id)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        var manifest = reconcileManifest()
        manifest.removeAll { $0.id == set.id }
        try commitManifest(manifest)
    }

    // MARK: - Export / Import (machine migration)

    public func export(_ set: BackupSet, to destination: URL) throws {
        let source = paths.backupSetDir(set.id)
        guard fileManager.fileExists(atPath: source.path) else {
            throw DatabaseError.connection("Backup files are missing for this set.")
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    @discardableResult
    public func importSet(from source: URL) throws -> BackupSet {
        let metaURL = source.appendingPathComponent("meta.json")
        guard let set = try? loadMeta(metaURL) else {
            throw DatabaseError.connection("The selected folder isn't a valid backup set.")
        }
        let id = UUID()
        let imported = BackupSet(
            id: id, kind: set.kind, engineVersion: set.engineVersion,
            profileName: set.profileName, host: set.host, databases: set.databases,
            createdAt: set.createdAt, sizeBytes: set.sizeBytes)
        let destination = paths.backupSetDir(id)
        try fileManager.createDirectory(at: paths.backups, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try writeMeta(imported, in: destination)
        var manifest = reconcileManifest()
        manifest.removeAll { $0.id == id }
        manifest.append(imported)
        try commitManifest(manifest)
        return imported
    }

    // MARK: - Manifest persistence

    private func reconcileManifest() -> [BackupSet] {
        let onDisk = scanSetDirectories()
        let manifest = loadManifest()
        var byID: [UUID: BackupSet] = [:]
        for set in onDisk { byID[set.id] = set }
        for set in manifest where byID[set.id] != nil { byID[set.id] = set }
        let reconciled = Array(byID.values)
        if reconciled.count != manifest.count
            || Set(reconciled.map(\.id)) != Set(manifest.map(\.id)) {
            try? commitManifest(reconciled)
        }
        return reconciled
    }

    private func scanSetDirectories() -> [BackupSet] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: paths.backups, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return entries.compactMap { entry in
            try? loadMeta(entry.appendingPathComponent("meta.json"))
        }
    }

    private func loadManifest() -> [BackupSet] {
        guard let data = try? Data(contentsOf: paths.backupManifest),
              let decoded = try? Self.decoder.decode([BackupSet].self, from: data) else { return [] }
        return decoded
    }

    private func commitManifest(_ sets: [BackupSet]) throws {
        let data = try Self.encoder.encode(sets)
        let temp = paths.backups.appendingPathComponent(".manifest-\(UUID().uuidString).tmp")
        try data.write(to: temp, options: .atomic)
        defer { try? fileManager.removeItem(at: temp) }
        if fileManager.fileExists(atPath: paths.backupManifest.path) {
            _ = try fileManager.replaceItemAt(paths.backupManifest, withItemAt: temp)
        } else {
            try fileManager.moveItem(at: temp, to: paths.backupManifest)
        }
    }

    private func writeMeta(_ set: BackupSet, in setDir: URL) throws {
        let data = try Self.encoder.encode(set)
        try data.write(to: setDir.appendingPathComponent("meta.json"), options: .atomic)
    }

    private func loadMeta(_ url: URL) throws -> BackupSet {
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(BackupSet.self, from: data)
    }

    // MARK: - Path safety

    /// Reject names that escape the set directory once joined (`.`/`..`, separators) — remote
    /// `listDatabases()` names are untrusted. SQL-identifier validation permits `.`, so this is a
    /// separate filesystem-path check applied before every write and delete.
    static func safeArtifactURL(database: String, fileExtension: String, in setDir: URL) throws -> URL {
        try DumpService.validateIdentifier(database, label: "database")
        guard database != "." && database != ".." && !database.contains("/") else {
            throw DatabaseError.connection("Illegal database name for a backup file.")
        }
        let name = fileExtension.isEmpty ? database : "\(database).\(fileExtension)"
        let candidate = setDir.appendingPathComponent(name).standardizedFileURL
        let parent = setDir.standardizedFileURL
        guard candidate.deletingLastPathComponent().path == parent.path else {
            throw DatabaseError.connection("Backup file path escapes the backup set directory.")
        }
        return candidate
    }

    // MARK: - Helpers

    private static func directorySize(_ url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true, let size = values?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
