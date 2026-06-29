import XCTest
@testable import KTStackKit

final class MongoDriverIntegrationTests: XCTestCase {
    private func makeDriver() throws -> MongoDriver {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KTSTACK_DB_IT"] == "1",
            "Set KTSTACK_DB_IT=1 with the MongoDB engine installed + running on :27017."
        )
        let catalog = ServiceBinaryCatalog(paths: AppSupportPaths())
        try XCTSkipUnless(catalog.isInstalled(.mongodb), "MongoDB engine not installed.")
        return MongoDriver(profile: .managedMongo, password: nil)
    }

    private let database = "ktstack_it"
    private let collection = "phase8_docs"

    func testPingSucceeds() async throws {
        let driver = try makeDriver()
        try await driver.ping()
    }

    func testListDatabasesIncludesAdmin() async throws {
        let driver = try makeDriver()
        let names = try await driver.listDatabases().map(\.name)
        XCTAssertTrue(names.contains("admin"))
    }

    func testCRUDLifecycle() async throws {
        let driver = try makeDriver()
        try await driver.dropCollection(database: database, collection: collection)
        try await driver.createCollection(database: database, name: collection)

        let collections = try await driver.listCollections(database: database).map(\.name)
        XCTAssertTrue(collections.contains(collection))

        try await driver.insert(
            database: database,
            collection: collection,
            json: #"{"_id":{"$oid":"507f1f77bcf86cd799439011"},"name":"alice","age":30}"#
        )

        var found = try await driver.find(
            database: database,
            collection: collection,
            filterJSON: #"{"name":"alice"}"#,
            limit: 10,
            skip: 0
        )
        XCTAssertEqual(found.count, 1)
        let record = try XCTUnwrap(found.first)
        XCTAssertEqual(record.id, "507f1f77bcf86cd799439011")

        try await driver.update(
            database: database,
            collection: collection,
            record: record,
            json: #"{"name":"alice","age":31}"#
        )
        found = try await driver.find(
            database: database,
            collection: collection,
            filterJSON: #"{"name":"alice"}"#,
            limit: 10,
            skip: 0
        )
        XCTAssertTrue(found.first?.json.contains("31") ?? false)

        let aggregated = try await driver.aggregate(
            database: database,
            collection: collection,
            pipelineJSON: #"[{"$match":{"name":"alice"}},{"$project":{"name":1}}]"#,
            limit: 10
        )
        XCTAssertEqual(aggregated.count, 1)

        try await driver.delete(database: database, collection: collection, record: record)
        found = try await driver.find(
            database: database,
            collection: collection,
            filterJSON: nil,
            limit: 10,
            skip: 0
        )
        XCTAssertTrue(found.isEmpty)

        try await driver.dropCollection(database: database, collection: collection)
    }

    func testUpdateRejectsChangedID() async {
        let driver = MongoDriver(profile: .managedMongo, password: nil)
        let record = DocumentRecord(id: "1", json: "{\"_id\":1}", identifierJSON: "1")
        do {
            try await driver.update(
                database: database,
                collection: collection,
                record: record,
                json: #"{"_id":2,"name":"x"}"#
            )
            XCTFail("expected the changed _id to be rejected")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message.contains("_id"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testReadOnlyConnectionRefusesWrites() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KTSTACK_DB_IT"] == "1", "Integration only.")
        let readOnly = ConnectionProfile(
            name: "ro",
            kind: .mongodb,
            host: "127.0.0.1",
            port: 27017,
            user: "",
            database: "admin",
            tlsMode: .disable,
            readOnly: true
        )
        let driver = MongoDriver(profile: readOnly, password: nil)
        do {
            try await driver.insert(database: database, collection: collection, json: #"{"a":1}"#)
            XCTFail("expected a read-only failure")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message.contains("read-only"))
        }
    }
}
