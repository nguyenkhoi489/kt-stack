import NIOCore
import XCTest
@testable import KTStackKit

/// Engine-free coverage of the query-result model. The NULL-vs-value mapping is the part the grid
/// depends on, so it is proven here without a live MySQL (CI-blocking). The live connect path is in
/// the integration suite below.
final class QueryResultSetMappingTests: XCTestCase {
    func testTextCellsMapNullBufferToNil() {
        let values: [ByteBuffer?] = [ByteBuffer(string: "alpha"), nil, ByteBuffer(string: "")]
        let cells = QueryResultSet.textCells(values)
        XCTAssertEqual(cells, ["alpha", nil, ""]) // NULL is nil; empty string stays distinct
    }

    func testTextCellsPreserveOrderAndDuplicatePositions() {
        let values: [ByteBuffer?] = [ByteBuffer(string: "1"), ByteBuffer(string: "1"), nil]
        XCTAssertEqual(QueryResultSet.textCells(values), ["1", "1", nil])
    }

    func testResultSetReportsRowCountAndEquatable() {
        let a = QueryResultSet(columns: ["x"], rows: [["1"], [nil]])
        let b = QueryResultSet(columns: ["x"], rows: [["1"], [nil]])
        XCTAssertEqual(a.rowCount, 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, QueryResultSet(columns: ["y"], rows: [["1"], [nil]]))
    }

    func testColumnsTextRowsInitKeepsHeadersWithZeroRows() {
        // Column metadata is captured independently of rows, so an empty result still carries its
        // headers — the grid shows "no matching rows" under real titles, not a blank no-result state.
        let empty = QueryResultSet(columns: ["a", "b"], textRows: [])
        XCTAssertEqual(empty.columns, ["a", "b"])
        XCTAssertEqual(empty.rowCount, 0)
    }
}

/// Opt-in integration coverage: proves the driver connects to the managed MySQL, maps runtime
/// columns, and preserves NULLs. Gated on `KTSTACK_DB_IT=1` AND an installed engine so a clean CI box
/// (no engine) skips rather than fails. The engine must also be running on 3306.
final class MySQLProbeIntegrationTests: XCTestCase {
    private func requireOptIn() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KTSTACK_DB_IT"] == "1",
            "Set KTSTACK_DB_IT=1 with the MySQL engine installed + running on :3306."
        )
        let catalog = ServiceBinaryCatalog(paths: AppSupportPaths())
        try XCTSkipUnless(catalog.isInstalled(.mysql), "MySQL engine not installed.")
    }

    func testConnectListsDatabases() async throws {
        try requireOptIn()
        let result = try await MySQLProbe.run(sql: "SHOW DATABASES")
        XCTAssertEqual(result.columns, ["Database"])
        XCTAssertGreaterThanOrEqual(result.rowCount, 1)
        XCTAssertTrue(result.rows.contains { $0.first.flatMap { $0 } == "mysql" })
    }

    func testSelectMapsDynamicColumnsAndNull() async throws {
        try requireOptIn()
        let result = try await MySQLProbe.run(sql: "SELECT 1 AS a, NULL AS b, 'x' AS c")
        XCTAssertEqual(result.columns, ["a", "b", "c"])
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0][0], "1")
        XCTAssertNil(result.rows[0][1]) // SQL NULL preserved as nil
        XCTAssertEqual(result.rows[0][2], "x")
    }

    func testZeroRowSelectStillReturnsColumns() async throws {
        try requireOptIn()
        let result = try await MySQLProbe.run(sql: "SELECT 1 AS a, 2 AS b WHERE 1 = 0")
        XCTAssertEqual(result.columns, ["a", "b"]) // headers survive an empty result set
        XCTAssertEqual(result.rowCount, 0)
    }
}
