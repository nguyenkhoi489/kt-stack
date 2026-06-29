import Foundation

public struct BackupSession: Sendable {
    public let library: BackupLibrary
    public let resolveEngineVersion: @Sendable (DatabaseKind) -> String?

    public init(
        library: BackupLibrary = BackupLibrary(),
        resolveEngineVersion: @escaping @Sendable (DatabaseKind) -> String? = { _ in nil }
    ) {
        self.library = library
        self.resolveEngineVersion = resolveEngineVersion
    }

    public static func managed(paths: AppSupportPaths = AppSupportPaths()) -> BackupSession {
        return BackupSession(
            library: BackupLibrary(paths: paths),
            resolveEngineVersion: { kind in
                let catalog = ServiceBinaryCatalog(paths: paths)
                let store = ServiceVersionStore(paths: paths, catalog: catalog)
                switch kind {
                case .mysql: return store.activeVersion(.mysql)
                case .postgres: return store.activeVersion(.postgres)
                case .mongodb: return store.activeVersion(.mongodb)
                case .sqlite: return nil
                }
            }
        )
    }

    public func provider(for kind: DatabaseKind) -> BackupProviderResult {
        BackupProviderFactory.make(for: kind)
    }

    public func create(
        profile: ConnectionProfile,
        password: String?,
        databases: [String]
    ) async throws -> BackupSet {
        guard let provider = providerOrThrow(profile.kind) else {
            throw DatabaseError.connection("Backup isn't available for \(profile.kind.rawValue).")
        }
        return try await library.create(
            kind: profile.kind, profile: profile, databases: databases,
            using: provider, password: password,
            engineVersion: resolveEngineVersion(profile.kind)
        )
    }

    public func restore(
        set: BackupSet,
        database: String,
        profile: ConnectionProfile,
        password: String?,
        target: RestoreTarget
    ) async throws {
        guard set.kind == profile.kind else {
            throw DatabaseError.connection(
                "Backup engine (\(set.kind.rawValue)) doesn't match the active connection (\(profile.kind.rawValue))."
            )
        }
        try requireCompatibleVersion(set: set, kind: profile.kind)
        guard let provider = providerOrThrow(profile.kind) else {
            throw DatabaseError.connection("Restore isn't available for \(profile.kind.rawValue).")
        }
        let artifact = artifactURL(
            in: library.directory(for: set),
            database: database,
            provider: provider
        )
        try await provider.restore(
            profile: profile,
            password: password,
            from: artifact,
            into: target
        )
    }

    public func artifactURL(in setDir: URL, database: String, provider: BackupProvider) -> URL {
        setDir.appendingPathComponent(provider.artifactName(for: database))
    }

    public func delete(_ set: BackupSet) throws {
        try library.delete(set)
    }

    public func exportSet(_ set: BackupSet, to destination: URL) throws {
        try library.export(set, to: destination)
    }

    private func providerOrThrow(_ kind: DatabaseKind) -> BackupProvider? {
        if case let .available(provider) = BackupProviderFactory.make(for: kind) { return provider }
        return nil
    }

    private func requireCompatibleVersion(set: BackupSet, kind: DatabaseKind) throws {
        guard let stored = set.engineVersion,
              let current = resolveEngineVersion(kind) else { return }
        guard Self.majorVersion(stored) != Self.majorVersion(current) else { return }
        throw DatabaseError.connection(
            "This backup was made on \(kind.rawValue) \(stored); the installed engine is \(current). "
                + "Restore aborted before any destructive step."
        )
    }

    static func majorVersion(_ version: String) -> String {
        version.split(whereSeparator: { $0 == "." || $0 == "-" }).first.map(String.init) ?? version
    }

    public static func userDatabaseNames(_ names: [String], for kind: DatabaseKind) -> [String] {
        let system: Set<String> = switch kind {
        case .mysql: ["information_schema", "performance_schema", "mysql", "sys"]
        case .postgres: ["template0", "template1"]
        case .mongodb: ["admin", "local", "config"]
        case .sqlite: []
        }
        return names.filter { !system.contains($0.lowercased()) }
    }
}
