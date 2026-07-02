import XCTest
@testable import KTStackKit

/// SQLite is file-based and GRDB vendors its engine, so these run in CI with no external service —
/// each test spins up a throwaway `.db`. Covers the full editor surface: DDL/DML via the SQL runner,
/// typed-cell round-trips, schema introspection (PK + index), row CRUD with the one-row guard, and
/// the read-only contract enforced by opening the file read-only.
final class SQLiteDriverTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-sqlite-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeDriver(readOnly: Bool = false) -> SQLiteDriver {
        let path = tempDir.appendingPathComponent("test.db").path
        let profile = ConnectionProfile(
            name: "t",
            kind: .sqlite,
            host: "",
            port: 0,
            user: "",
            database: SQLiteDriver.mainDatabase,
            filePath: path,
            readOnly: readOnly
        )
        return SQLiteDriver(profile: profile)
    }

    private func seedSchema(_ driver: SQLiteDriver) async throws {
        _ = try await driver.query("""
        CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT NOT NULL, score REAL, data BLOB)
        """, database: nil)
    }

    func testMissingFilePathFailsClearly() async {
        let profile = ConnectionProfile(
            name: "x",
            kind: .sqlite,
            host: "",
            port: 0,
            user: "",
            database: "main",
            filePath: nil
        )
        let driver = SQLiteDriver(profile: profile)
        do { try await driver.ping(); XCTFail("expected failure") }
        catch { XCTAssertTrue(error is DatabaseError) }
    }

    func testUnopenablePathMapsToFileAccessMessage() {
        // A directory can't be opened as a database file (SQLITE_CANTOPEN); the error must guide the
        // user to the pickers, not leak a raw SQLite message (mirrors a TCC-blocked path).
        let profile = ConnectionProfile(
            name: "x", kind: .sqlite, host: "", port: 0, user: "",
            database: SQLiteDriver.mainDatabase, filePath: tempDir.path, readOnly: false
        )
        XCTAssertThrowsError(try SQLiteDriver.makeQueue(profile: profile)) { error in
            guard case let DatabaseError.connection(message) = error else {
                return XCTFail("expected .connection, got \(error)")
            }
            XCTAssertTrue(message.contains("macOS blocked access"), "got: \(message)")
        }
    }

    func testCreateInsertBrowseRoundTripsTypedCells() async throws {
        let driver = makeDriver()
        try await seedSchema(driver)
        _ = try await driver.query(
            "INSERT INTO notes (id, body, score, data) VALUES (1, 'hello', 1.5, NULL)", database: nil
        )

        let page = try await driver.paginatedRows(
            database: "main",
            table: "notes",
            limit: 100,
            offset: 0
        )
        XCTAssertEqual(page.columnNames, ["id", "body", "score", "data"])
        XCTAssertEqual(page.rows.count, 1)
        XCTAssertEqual(page.rows[0][0], .int(1))
        XCTAssertEqual(page.rows[0][1], .text("hello"))
        XCTAssertEqual(page.rows[0][2], .double(1.5))
        XCTAssertEqual(page.rows[0][3], .null)
    }

    func testZeroRowQueryPreservesColumns() async throws {
        let driver = makeDriver()
        try await seedSchema(driver)
        let result = try await driver.query("SELECT id, body FROM notes WHERE 1 = 0", database: nil)
        XCTAssertEqual(result.columnNames, ["id", "body"])
        XCTAssertEqual(result.rowCount, 0)
    }

    func testListTablesExcludesInternalAndFlagsViews() async throws {
        let driver = makeDriver()
        try await seedSchema(driver)
        _ = try await driver.query("CREATE VIEW recent AS SELECT * FROM notes", database: nil)
        let tables = try await driver.listTables(database: "main")
        XCTAssertEqual(tables.first { $0.name == "notes" }?.isView, false)
        XCTAssertEqual(tables.first { $0.name == "recent" }?.isView, true)
        XCTAssertFalse(tables.contains { $0.name.hasPrefix("sqlite_") })
    }

    func testColumnsReportPrimaryKeyAndNullability() async throws {
        let driver = makeDriver()
        try await seedSchema(driver)
        let columns = try await driver.columns(database: "main", table: "notes")
        XCTAssertEqual(columns.primaryKeyColumns.map(\.name), ["id"])
        XCTAssertEqual(columns.first { $0.name == "body" }?.isNullable, false)
        XCTAssertEqual(columns.first { $0.name == "score" }?.isNullable, true)
    }

    func testIndexesAreIntrospected() async throws {
        let driver = makeDriver()
        try await seedSchema(driver)
        _ = try await driver.query("CREATE UNIQUE INDEX idx_body ON notes (body)", database: nil)
        let indexes = try await driver.indexes(database: "main", table: "notes")
        let idx = try XCTUnwrap(indexes.first { $0.columns == ["body"] })
        XCTAssertTrue(idx.isUnique)
    }

    func testRowCRUDWithBlob() async throws {
        let driver = makeDriver()
        try await seedSchema(driver)
        let blob = Data([0x00, 0x01, 0xFF])
        try await driver.insert(database: "main", table: "notes", values: [
            ColumnValue(column: "id", value: .int(7)),
            ColumnValue(column: "body", value: .text("orig")),
            ColumnValue(column: "data", value: .blob(blob)),
        ])

        var rows = try await driver.paginatedRows(
            database: "main",
            table: "notes",
            limit: 10,
            offset: 0
        ).rows
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0][3], .blob(blob))

        try await driver.update(
            database: "main",
            table: "notes",
            values: [ColumnValue(column: "body", value: .text("edited"))],
            key: [ColumnValue(column: "id", value: .int(7))]
        )
        rows = try await driver.paginatedRows(
            database: "main",
            table: "notes",
            limit: 10,
            offset: 0
        ).rows
        XCTAssertEqual(rows[0][1], .text("edited"))

        try await driver.delete(
            database: "main",
            table: "notes",
            key: [ColumnValue(column: "id", value: .int(7))]
        )
        let after = try await driver.paginatedRows(
            database: "main",
            table: "notes",
            limit: 10,
            offset: 0
        )
        XCTAssertEqual(after.rowCount, 0)
    }

    func testDeleteAffectingNoRowIsRejected() async throws {
        let driver = makeDriver()
        try await seedSchema(driver)
        do {
            try await driver.delete(
                database: "main",
                table: "notes",
                key: [ColumnValue(column: "id", value: .int(999))]
            )
            XCTFail("expected the zero-row guard to reject")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }

    func testReadOnlyConnectionRejectsWrites() async throws {
        try await seedSchema(makeDriver()) // create the file writable first
        let readOnly = makeDriver(readOnly: true)
        do {
            try await readOnly.insert(database: "main", table: "notes", values: [
                ColumnValue(column: "id", value: .int(1)),
                ColumnValue(column: "body", value: .text("nope")),
            ])
            XCTFail("expected a read-only rejection")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }
}
