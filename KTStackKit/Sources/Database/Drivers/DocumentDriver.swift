import Foundation

public protocol DocumentDriver: DatabaseDriver {
    func listDatabases() async throws -> [DatabaseInfo]

    func listCollections(database: String) async throws -> [CollectionInfo]

    func find(
        database: String,
        collection: String,
        filterJSON: String?,
        limit: Int,
        skip: Int
    ) async throws -> [DocumentRecord]

    func aggregate(
        database: String,
        collection: String,
        pipelineJSON: String,
        limit: Int
    ) async throws -> [DocumentRecord]

    func insert(database: String, collection: String, json: String) async throws

    func update(
        database: String,
        collection: String,
        record: DocumentRecord,
        json: String
    ) async throws

    func delete(database: String, collection: String, record: DocumentRecord) async throws

    func createCollection(database: String, name: String) async throws

    func dropCollection(database: String, collection: String) async throws
}
