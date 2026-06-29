import XCTest
@testable import KTStackKit

/// Opt-in integration coverage for `MySQLDriver` row CRUD against the managed engine. Gated on
/// `KTSTACK_DB_IT=1` AND an installed engine running on :3306, so a clean CI box skips. Proves the
/// insert→read→update→delete round-trip, composite-key updates, and the affect-exactly-one transaction
/// guard that rolls back a write touching ≠1 row. Each test owns a throwaway database it drops at the end.
final class MySQLDriverCRUDTests: XCTestCase {
    private let schema = "ktstack_crud_it"

    private func makeDriver() throws -> MySQLDriver {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KTSTACK_DB_IT"] == "1",
            "Set KTSTACK_DB_IT=1 with the MySQL engine installed + running on :3306."
        )
        let catalog = ServiceBinaryCatalog(paths: AppSupportPaths())
        try XCTSkipUnless(catalog.isInstalled(.mysql), "MySQL engine not installed.")
        return MySQLDriver(profile: .managedMySQL, password: nil)
    }

    private func resetSchema(_ driver: MySQLDriver) async throws {
        _ = try await driver.query("DROP DATABASE IF EXISTS \(schema)", database: nil)
        _ = try await driver.query("CREATE DATABASE \(schema)", database: nil)
    }

    private func dropSchema(_ driver: MySQLDriver) async {
        _ = try? await driver.query("DROP DATABASE IF EXISTS \(schema)", database: nil)
    }

    func testInsertReadUpdateDeleteRoundTrip() async throws {
        let driver = try makeDriver()
        try await resetSchema(driver)
        defer { Task { await dropSchema(driver) } }
        _ = try await driver.query(
            "CREATE TABLE \(schema).t (id INT PRIMARY KEY, name VARCHAR(50))", database: nil
        )

        try await driver.insert(
            database: schema,
            table: "t",
            values: [
                ColumnValue(column: "id", value: .int(1)),
                ColumnValue(column: "name", value: .text("alice")),
            ]
        )
        var page = try await driver.paginatedRows(database: schema, table: "t", limit: 10, offset: 0)
        XCTAssertEqual(page.rowCount, 1)
        XCTAssertEqual(page.rows[0][1], .text("alice"))

        try await driver.update(
            database: schema,
            table: "t",
            values: [ColumnValue(column: "name", value: .text("bob"))],
            key: [ColumnValue(column: "id", value: .int(1))]
        )
        page = try await driver.paginatedRows(database: schema, table: "t", limit: 10, offset: 0)
        XCTAssertEqual(page.rows[0][1], .text("bob"))

        try await driver.delete(
            database: schema,
            table: "t",
            key: [ColumnValue(column: "id", value: .int(1))]
        )
        page = try await driver.paginatedRows(database: schema, table: "t", limit: 10, offset: 0)
        XCTAssertEqual(page.rowCount, 0)
    }

    func testCompositeKeyUpdateAffectsOneRow() async throws {
        let driver = try makeDriver()
        try await resetSchema(driver)
        defer { Task { await dropSchema(driver) } }
        _ = try await driver.query(
            "CREATE TABLE \(schema).t2 (a INT, b INT, v INT, PRIMARY KEY (a, b))", database: nil
        )
        try await driver.insert(database: schema, table: "t2", values: [
            ColumnValue(column: "a", value: .int(1)), ColumnValue(column: "b", value: .int(2)),
            ColumnValue(column: "v", value: .int(10)),
        ])
        try await driver.insert(database: schema, table: "t2", values: [
            ColumnValue(column: "a", value: .int(1)), ColumnValue(column: "b", value: .int(3)),
            ColumnValue(column: "v", value: .int(20)),
        ])

        // Update only (1,2): the composite key must not touch (1,3).
        try await driver.update(
            database: schema,
            table: "t2",
            values: [ColumnValue(column: "v", value: .int(99))],
            key: [
                ColumnValue(column: "a", value: .int(1)),
                ColumnValue(column: "b", value: .int(2)),
            ]
        )
        let page = try await driver.paginatedRows(database: schema, table: "t2", limit: 10, offset: 0)
        func v(forB b: Int64) -> Cell? {
            page.rows.first { $0[1] == .int(b) }?[2]
        } // row by b → v
        XCTAssertEqual(v(forB: 2), .int(99))
        XCTAssertEqual(v(forB: 3), .int(20)) // untouched
    }

    func testWriteAffectingMultipleRowsRollsBack() async throws {
        let driver = try makeDriver()
        try await resetSchema(driver)
        defer { Task { await dropSchema(driver) } }
        // No unique key, two identical `tag` values → a key on `tag` matches both rows.
        _ = try await driver.query(
            "CREATE TABLE \(schema).t3 (tag INT, v INT)", database: nil
        )
        for _ in 0..<2 {
            _ = try await driver.query("INSERT INTO \(schema).t3 (tag, v) VALUES (5, 1)", database: nil)
        }

        do {
            try await driver.update(
                database: schema,
                table: "t3",
                values: [ColumnValue(column: "v", value: .int(2))],
                key: [ColumnValue(column: "tag", value: .int(5))]
            )
            XCTFail("expected the affect-exactly-one guard to throw")
        } catch {
            // Expected — guard aborts a multi-row write.
        }
        // Rolled back: both rows still v = 1.
        let page = try await driver.paginatedRows(database: schema, table: "t3", limit: 10, offset: 0)
        XCTAssertEqual(page.rows.map { $0[1] }, [.int(1), .int(1)])
    }
}
