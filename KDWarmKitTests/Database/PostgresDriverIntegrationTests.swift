import XCTest
@testable import KDWarmKit

/// Opt-in integration coverage for `PostgresDriver` against the managed engine. Gated on `KDWARM_DB_IT=1`
/// AND an installed engine, so a clean CI box skips rather than fails. The engine must be running on
/// :5432 with trust auth (the managed layout). Proves the driver returns real schema + typed query
/// results, enforces the one-row write guard, and is safe under rapid concurrent re-query.
final class PostgresDriverIntegrationTests: XCTestCase {

    private func makeDriver() throws -> PostgresDriver {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KDWARM_DB_IT"] == "1",
                          "Set KDWARM_DB_IT=1 with PostgreSQL installed + running on :5432.")
        let catalog = ServiceBinaryCatalog(paths: AppSupportPaths())
        try XCTSkipUnless(catalog.isInstalled(.postgres), "PostgreSQL engine not installed.")
        return PostgresDriver(profile: .managedPostgres, password: nil)
    }

    func testPingSucceeds() async throws {
        let driver = try makeDriver()
        try await driver.ping()
    }

    func testListDatabasesReturnsSchemas() async throws {
        let driver = try makeDriver()
        let names = try await driver.listDatabases().map(\.name)
        XCTAssertTrue(names.contains("public"))
        XCTAssertTrue(names.contains("pg_catalog"))
    }

    func testListTablesAndColumnsForCatalog() async throws {
        let driver = try makeDriver()
        let tables = try await driver.listTables(database: "pg_catalog").map(\.name)
        XCTAssertTrue(tables.contains("pg_class"))

        let columns = try await driver.columns(database: "pg_catalog", table: "pg_class")
        XCTAssertFalse(columns.isEmpty)
        XCTAssertTrue(columns.contains { $0.name == "relname" })
    }

    func testQueryMapsTypedCellsAndNull() async throws {
        let driver = try makeDriver()
        let result = try await driver.query(
            "SELECT 1::int8 AS i, 1.5::float8 AS d, NULL::text AS n, 'x'::text AS s, true AS b",
            database: nil)
        XCTAssertEqual(result.columnNames, ["i", "d", "n", "s", "b"])
        XCTAssertEqual(result.rows[0][0], .int(1))
        XCTAssertEqual(result.rows[0][1], .double(1.5))
        XCTAssertEqual(result.rows[0][2], .null)
        XCTAssertEqual(result.rows[0][3], .text("x"))
        XCTAssertEqual(result.rows[0][4], .bool(true))
    }

    func testPaginationLimitsRows() async throws {
        let driver = try makeDriver()
        let page = try await driver.paginatedRows(database: "pg_catalog", table: "pg_type",
                                                  limit: 5, offset: 0)
        XCTAssertLessThanOrEqual(page.rowCount, 5)
        XCTAssertFalse(page.columns.isEmpty)
    }

    func testRowCRUDRoundTrip() async throws {
        let driver = try makeDriver()
        _ = try await driver.query("DROP TABLE IF EXISTS kdwarm_it", database: nil)
        _ = try await driver.query(
            "CREATE TABLE kdwarm_it (id bigint PRIMARY KEY, name text)", database: nil)
        defer { Task { _ = try? await driver.query("DROP TABLE IF EXISTS kdwarm_it", database: nil) } }

        try await driver.insert(database: "public", table: "kdwarm_it", values: [
            ColumnValue(column: "id", value: .int(1)),
            ColumnValue(column: "name", value: .text("orig")),
        ])
        try await driver.update(database: "public", table: "kdwarm_it",
                                values: [ColumnValue(column: "name", value: .text("edited"))],
                                key: [ColumnValue(column: "id", value: .int(1))])
        let rows = try await driver.paginatedRows(database: "public", table: "kdwarm_it",
                                                  limit: 10, offset: 0).rows
        XCTAssertEqual(rows.first?[1], .text("edited"))

        try await driver.delete(database: "public", table: "kdwarm_it",
                                key: [ColumnValue(column: "id", value: .int(1))])
        let after = try await driver.paginatedRows(database: "public", table: "kdwarm_it",
                                                   limit: 10, offset: 0)
        XCTAssertEqual(after.rowCount, 0)
    }

    func testDeleteAffectingNoRowIsRejected() async throws {
        let driver = try makeDriver()
        _ = try await driver.query("DROP TABLE IF EXISTS kdwarm_it", database: nil)
        _ = try await driver.query(
            "CREATE TABLE kdwarm_it (id bigint PRIMARY KEY, name text)", database: nil)
        defer { Task { _ = try? await driver.query("DROP TABLE IF EXISTS kdwarm_it", database: nil) } }
        do {
            try await driver.delete(database: "public", table: "kdwarm_it",
                                    key: [ColumnValue(column: "id", value: .int(999))])
            XCTFail("expected the zero-row guard to reject")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }

    func testReadOnlyConnectionRejectsWrites() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KDWARM_DB_IT"] == "1",
                          "Set KDWARM_DB_IT=1 with PostgreSQL installed + running on :5432.")
        let catalog = ServiceBinaryCatalog(paths: AppSupportPaths())
        try XCTSkipUnless(catalog.isInstalled(.postgres), "PostgreSQL engine not installed.")
        // A read-only managed connection: `SET default_transaction_read_only = on` must make even DDL fail.
        let profile = ConnectionProfile(name: "ro", kind: .postgres, host: "127.0.0.1", port: 5432,
                                        user: "postgres", database: "postgres",
                                        tlsMode: .disable, readOnly: true)
        let driver = PostgresDriver(profile: profile, password: nil)
        do {
            _ = try await driver.query("CREATE TABLE kdwarm_ro_guard (i int)", database: nil)
            _ = try? await driver.query("DROP TABLE IF EXISTS kdwarm_ro_guard", database: nil)
            XCTFail("expected a server-side read-only rejection")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }

    func testConcurrentQueriesAreRaceFree() async throws {
        let driver = try makeDriver()
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await driver.query("SELECT 1 AS n", database: nil).rowCount
                }
            }
            var total = 0
            for try await count in group { total += count }
            XCTAssertEqual(total, 20)
        }
    }
}
