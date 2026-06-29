import Foundation
import MongoKitten

public extension MongoDriver {
    func insert(database: String, collection: String, json: String) async throws {
        try ensureWritable()
        let document = try MongoJSONMapper.document(fromJSON: json)
        try await withPool { pool in
            _ = try await pool[database][collection].insert(document)
        }
    }

    func update(
        database: String,
        collection: String,
        record: DocumentRecord,
        json: String
    ) async throws {
        try ensureWritable()
        let document = try MongoJSONMapper.document(fromJSON: json)
        if let editedID = document["_id"],
           let editedIDJSON = MongoJSONMapper.identifierJSON(for: editedID),
           editedIDJSON != record.identifierJSON
        {
            throw DatabaseError.syntax("The _id field can't be changed; keep the original value or remove it.")
        }
        let filter = try matchFilter(for: record)
        try await withPool { pool in
            _ = try await pool[database][collection].updateOne(where: filter, to: document)
        }
    }

    func delete(database: String, collection: String, record: DocumentRecord) async throws {
        try ensureWritable()
        let filter = try matchFilter(for: record)
        try await withPool { pool in
            _ = try await pool[database][collection].deleteOne(where: filter)
        }
    }

    func createCollection(database: String, name: String) async throws {
        try ensureWritable()
        try await withPool { pool in
            let collection = pool[database][name]
            _ = try await collection.insert(Self.collectionInitMarker)
            _ = try await collection.deleteAll(where: Self.collectionInitMarker)
        }
    }

    func dropCollection(database: String, collection: String) async throws {
        try ensureWritable()
        try await withPool { pool in
            try await pool[database][collection].drop()
        }
    }

    private func matchFilter(for record: DocumentRecord) throws -> Document {
        guard let identifierJSON = record.identifierJSON else {
            throw DatabaseError.unexpectedResponse("This document has no _id, so it can't be edited or deleted.")
        }
        let value = try MongoJSONMapper.value(fromJSON: identifierJSON)
        var filter = Document()
        filter["_id"] = value
        return filter
    }

    /// MongoKitten exposes no create-collection command, so an empty collection is materialized by
    /// inserting then removing a marker; MongoDB keeps the collection after it is emptied.
    private static var collectionInitMarker: Document {
        var document = Document()
        document["__ktstack_init"] = true
        return document
    }
}
