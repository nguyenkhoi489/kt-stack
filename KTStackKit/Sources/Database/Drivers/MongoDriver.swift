import Foundation
import MongoCore
import MongoKitten

public struct MongoDriver: DocumentDriver {
    public let kind: DatabaseKind = .mongodb

    let profile: ConnectionProfile
    let password: String?
    let catalog: ServiceBinaryCatalog

    public init(
        profile: ConnectionProfile,
        password: String?,
        catalog: ServiceBinaryCatalog = ServiceBinaryCatalog(paths: AppSupportPaths())
    ) {
        self.profile = profile
        self.password = password
        self.catalog = catalog
    }

    public func ping() async throws {
        try await withPool { _ in }
    }

    public func listDatabases() async throws -> [DatabaseInfo] {
        try await withPool { pool in
            try await pool.listDatabases().map { DatabaseInfo(name: $0.name) }
        }
    }

    public func listCollections(database: String) async throws -> [CollectionInfo] {
        try await withPool { pool in
            try await pool[database].listCollections().map { CollectionInfo(name: $0.name) }
        }
    }

    public func find(
        database: String,
        collection: String,
        filterJSON: String?,
        limit: Int,
        skip: Int
    ) async throws -> [DocumentRecord] {
        let filter = try filterDocument(filterJSON)
        return try await withPool { pool in
            let documents = try await pool[database][collection]
                .find(filter).skip(skip).limit(limit).drain()
            return try documents.map(Self.record(from:))
        }
    }

    public func aggregate(
        database: String,
        collection: String,
        pipelineJSON: String,
        limit: Int
    ) async throws -> [DocumentRecord] {
        var stages = try aggregateStages(pipelineJSON)
        var limitStage = Document()
        limitStage["$limit"] = limit
        stages.append(RawAggregateStage(stage: limitStage))
        return try await withPool { pool in
            let pipeline = AggregateBuilderPipeline(stages: stages, collection: pool[database][collection])
            let documents = try await pipeline.drain()
            return try documents.map(Self.record(from:))
        }
    }

    func withPool<T: Sendable>(_ body: @Sendable (MongoConnectionPool) async throws -> T) async throws -> T {
        try preflightInstalled()
        let database: MongoDatabase
        do {
            database = try await MongoDatabase.connect(to: connectionSettings())
        } catch {
            throw mapError(error)
        }
        let pool = database.pool
        do {
            let result = try await body(pool)
            await (pool as? MongoCluster)?.disconnect()
            return result
        } catch {
            await (pool as? MongoCluster)?.disconnect()
            throw mapError(error)
        }
    }

    private func connectionSettings() throws -> ConnectionSettings {
        let target = profile.database.isEmpty ? "admin" : profile.database
        let authentication: ConnectionSettings.Authentication =
            profile.user.isEmpty ? .unauthenticated : .auto(username: profile.user, password: password ?? "")
        let loopback = ConnectionProfile.isLoopback(profile.host)
        return ConnectionSettings(
            authentication: authentication,
            authenticationSource: profile.user.isEmpty ? nil : "admin",
            hosts: [ConnectionSettings.Host(hostname: profile.host, port: profile.port)],
            targetDatabase: target,
            useSSL: !loopback && profile.tlsMode != .disable,
            verifySSLCertificates: profile.tlsMode == .verifyFull,
            connectTimeout: 10,
            socketTimeout: 30
        )
    }

    func preflightInstalled() throws {
        guard profile.isManaged else { return }
        guard catalog.isInstalled(.mongodb) else {
            throw DatabaseError.engineNotInstalled(kind: "MongoDB")
        }
    }

    func mapError(_ error: any Error) -> DatabaseError {
        MongoErrorMapper.map(
            error,
            isManaged: profile.isManaged,
            engineInstalled: catalog.isInstalled(.mongodb)
        )
    }

    func ensureWritable() throws {
        if profile.readOnly { throw DatabaseError.connection("This connection is read-only.") }
    }

    static func record(from document: Document) throws -> DocumentRecord {
        let identifier = document["_id"]
        return try DocumentRecord(
            id: MongoJSONMapper.displayString(for: identifier),
            json: MongoJSONMapper.encodedJSON(from: document, pretty: true),
            identifierJSON: MongoJSONMapper.identifierJSON(for: identifier)
        )
    }

    func filterDocument(_ json: String?) throws -> Document {
        guard let json, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Document()
        }
        return try MongoJSONMapper.document(fromJSON: json)
    }

    private func aggregateStages(_ json: String) throws -> [AggregateBuilderStage] {
        let value = try MongoJSONMapper.value(fromJSON: json)
        guard let array = value as? Document, array.isArray else {
            throw DatabaseError.syntax("An aggregation pipeline must be a JSON array of stages.")
        }
        return try array.values.map { element in
            guard let stage = element as? Document, !stage.isArray else {
                throw DatabaseError.syntax("Each aggregation stage must be a JSON object.")
            }
            return RawAggregateStage(stage: stage)
        }
    }
}

struct RawAggregateStage: AggregateBuilderStage {
    let stage: Document
    let minimalVersionRequired: WireVersion? = nil
}
