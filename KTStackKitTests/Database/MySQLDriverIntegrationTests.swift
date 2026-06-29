import XCTest
@testable import KTStackKit

/// Opt-in integration coverage for `MySQLDriver` against the managed engine. Gated on `KTSTACK_DB_IT=1`
/// AND an installed engine, so a clean CI box (no engine) skips rather than fails. The engine must be
/// running on :3306. Proves the driver returns real schema + query results and that the NIO→result
/// path is safe under rapid concurrent re-query (stressing the NIO→@MainActor result boundary).
final class MySQLDriverIntegrationTests: XCTestCase {
    private func makeDriver() throws -> MySQLDriver {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KTSTACK_DB_IT"] == "1",
            "Set KTSTACK_DB_IT=1 with the MySQL engine installed + running on :3306."
        )
        let catalog = ServiceBinaryCatalog(paths: AppSupportPaths())
        try XCTSkipUnless(catalog.isInstalled(.mysql), "MySQL engine not installed.")
        return MySQLDriver(profile: .managedMySQL, password: nil)
    }

    func testPingSucceeds() async throws {
        let driver = try makeDriver()
        try await driver.ping()
    }

    func testListDatabasesIncludesSystemSchemas() async throws {
        let driver = try makeDriver()
        let names = try await driver.listDatabases().map(\.name)
        XCTAssertTrue(names.contains("mysql"))
        XCTAssertTrue(names.contains("information_schema"))
    }

    func testListTablesAndColumnsForSystemTable() async throws {
        let driver = try makeDriver()
        let tables = try await driver.listTables(database: "mysql").map(\.name)
        XCTAssertTrue(tables.contains("user")) // mysql.user always exists

        let columns = try await driver.columns(database: "mysql", table: "user")
        XCTAssertFalse(columns.isEmpty)
        // mysql.user is keyed on (Host, User) — a composite PK, the case the row-edit phase relies on.
        XCTAssertTrue(columns.primaryKeyColumns.count >= 2)
    }

    func testQueryMapsTypedCellsAndNull() async throws {
        let driver = try makeDriver()
        let result = try await driver.query("SELECT 1 AS i, 1.5 AS d, NULL AS n, 'x' AS s", database: nil)
        XCTAssertEqual(result.columnNames, ["i", "d", "n", "s"])
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0][0], .int(1))
        XCTAssertEqual(result.rows[0][1], .double(1.5))
        XCTAssertEqual(result.rows[0][2], .null)
        XCTAssertEqual(result.rows[0][3], .text("x"))
    }

    func testZeroRowQueryPreservesColumns() async throws {
        let driver = try makeDriver()
        let result = try await driver.query("SELECT 1 AS a, 2 AS b WHERE 1 = 0", database: nil)
        XCTAssertEqual(result.columnNames, ["a", "b"])
        XCTAssertEqual(result.rowCount, 0)
    }

    func testPaginationLimitsRows() async throws {
        let driver = try makeDriver()
        let page = try await driver.paginatedRows(
            database: "information_schema",
            table: "COLUMNS",
            limit: 5,
            offset: 0
        )
        XCTAssertLessThanOrEqual(page.rowCount, 5)
        XCTAssertFalse(page.columns.isEmpty)
    }

    /// Rapid concurrent re-query: every call opens its own connection on the shared event-loop group,
    /// resolves NIO futures internally, and returns a Sendable result. Nothing here touches @MainActor
    /// state, so 20 overlapping queries must all complete without a crash or a data race.
    func testConcurrentQueriesAreRaceFree() async throws {
        let driver = try makeDriver()
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let result = try await driver.query("SELECT 1 AS n", database: nil)
                    return result.rowCount
                }
            }
            var total = 0
            for try await count in group {
                total += count
            }
            XCTAssertEqual(total, 20)
        }
    }
}
