import XCTest
@testable import KTStackKit

final class ForeignKeyIntrospectionTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-fk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeSQLiteDriver() -> SQLiteDriver {
        let path = tempDir.appendingPathComponent("test.db").path
        let profile = ConnectionProfile(
            name: "t",
            kind: .sqlite,
            host: "",
            port: 0,
            user: "",
            database: SQLiteDriver.mainDatabase,
            filePath: path,
            readOnly: false
        )
        return SQLiteDriver(profile: profile)
    }

    func testSQLiteForeignKeysSimpleRelation() async throws {
        let driver = makeSQLiteDriver()
        _ = try await driver.query("""
        CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)
        """, database: nil)
        _ = try await driver.query("""
        CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER REFERENCES users(id))
        """, database: nil)

        let relations = try await driver.foreignKeys(database: "main")

        XCTAssertEqual(relations.count, 1)
        let rel = try XCTUnwrap(relations.first)
        XCTAssertEqual(rel.fromTable, "orders")
        XCTAssertEqual(rel.fromColumn, "user_id")
        XCTAssertEqual(rel.toTable, "users")
        XCTAssertEqual(rel.toColumn, "id")
    }

    func testSQLiteForeignKeysCompositeRelation() async throws {
        let driver = makeSQLiteDriver()
        _ = try await driver.query("""
        CREATE TABLE parent (a INTEGER, b INTEGER, PRIMARY KEY (a, b))
        """, database: nil)
        _ = try await driver.query("""
        CREATE TABLE child (
            id INTEGER PRIMARY KEY,
            pa INTEGER,
            pb INTEGER,
            FOREIGN KEY (pa, pb) REFERENCES parent(a, b)
        )
        """, database: nil)

        let relations = try await driver.foreignKeys(database: "main")
        let childRelations = relations.filter { $0.fromTable == "child" }
        XCTAssertEqual(childRelations.count, 2)
        let cols = Set(childRelations.map { "\($0.fromColumn)->\($0.toColumn)" })
        XCTAssertEqual(cols, ["pa->a", "pb->b"])
    }

    func testSQLiteForeignKeysSelfReference() async throws {
        let driver = makeSQLiteDriver()
        _ = try await driver.query("""
        CREATE TABLE node (
            id INTEGER PRIMARY KEY,
            parent_id INTEGER REFERENCES node(id)
        )
        """, database: nil)

        let relations = try await driver.foreignKeys(database: "main")
        XCTAssertEqual(relations.count, 1)
        let rel = try XCTUnwrap(relations.first)
        XCTAssertEqual(rel.fromTable, "node")
        XCTAssertEqual(rel.toTable, "node")
        XCTAssertEqual(rel.fromColumn, "parent_id")
        XCTAssertEqual(rel.toColumn, "id")
    }

    func testSQLiteForeignKeysEmptyForSchemaWithoutRelations() async throws {
        let driver = makeSQLiteDriver()
        _ = try await driver.query("""
        CREATE TABLE solo (id INTEGER PRIMARY KEY)
        """, database: nil)

        let relations = try await driver.foreignKeys(database: "main")
        XCTAssertTrue(relations.isEmpty)
    }

    func testRowParserHandlesCompositeAndSelfRefRows() {
        let rows: [[Cell]] = [
            [.text("orders"), .text("user_id"), .text("users"), .text("id"), .text("fk_orders_user")],
            [.text("child"), .text("pa"), .text("parent"), .text("a"), .text("fk_child_pa_pb")],
            [.text("child"), .text("pb"), .text("parent"), .text("b"), .text("fk_child_pa_pb")],
            [.text("node"), .text("parent_id"), .text("node"), .text("id"), .text("fk_node_self")],
        ]
        let parsed = ForeignKeyRowParser.parseRelational(rows)
        XCTAssertEqual(parsed.count, 4)
        XCTAssertEqual(parsed[0].constraintName, "fk_orders_user")
        XCTAssertEqual(parsed[2].fromColumn, "pb")
        XCTAssertEqual(parsed[2].toColumn, "b")
        XCTAssertEqual(parsed[3].fromTable, "node")
        XCTAssertEqual(parsed[3].toTable, "node")
    }

    func testRowParserSkipsRowsWithMissingFields() {
        let rows: [[Cell]] = [
            [.text("orders"), .text("user_id"), .text("users"), .text("id")],
            [.text(""), .text("col"), .text("t"), .text("c")],
            [.text("orders"), .null, .text("users"), .text("id")],
        ]
        let parsed = ForeignKeyRowParser.parseRelational(rows)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertNil(parsed[0].constraintName)
    }
}
