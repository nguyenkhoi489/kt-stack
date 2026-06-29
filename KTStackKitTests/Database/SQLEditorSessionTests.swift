import XCTest
@testable import KTStackKit

final class SQLEditorSessionTests: XCTestCase {
    private let mysql = SQLDialect.forKind(.mysql)
    private let postgres = SQLDialect.forKind(.postgres)

    func testAppliesLimitToBareSelect() {
        let outcome = SQLAutoLimit.augment("SELECT * FROM users", dialect: mysql)
        XCTAssertTrue(outcome.applied)
        XCTAssertEqual(outcome.sql, "SELECT * FROM users LIMIT 1000 OFFSET 0")
    }

    func testAppliesLimitToLeadingWith() {
        let outcome = SQLAutoLimit.augment("WITH x AS (SELECT 1) SELECT * FROM x", dialect: mysql)
        XCTAssertTrue(outcome.applied)
        XCTAssertTrue(outcome.sql.hasSuffix("LIMIT 1000 OFFSET 0"))
    }

    func testKeepsExistingUserLimit() {
        let outcome = SQLAutoLimit.augment("SELECT * FROM users LIMIT 5", dialect: mysql)
        XCTAssertFalse(outcome.applied)
        XCTAssertEqual(outcome.sql, "SELECT * FROM users LIMIT 5")
    }

    func testIgnoresLimitInsideSubquery() {
        let outcome = SQLAutoLimit.augment(
            "SELECT * FROM (SELECT id FROM t LIMIT 5) AS x", dialect: mysql
        )
        XCTAssertFalse(outcome.applied)
    }

    func testIgnoresLimitInsideStringLiteral() {
        let outcome = SQLAutoLimit.augment("SELECT 'has LIMIT word' AS note", dialect: mysql)
        XCTAssertTrue(outcome.applied)
        XCTAssertEqual(outcome.sql, "SELECT 'has LIMIT word' AS note LIMIT 1000 OFFSET 0")
    }

    func testIgnoresLimitInsideLineComment() {
        let outcome = SQLAutoLimit.augment("SELECT * FROM t -- LIMIT 5", dialect: mysql)
        XCTAssertTrue(outcome.applied)
        XCTAssertTrue(outcome.sql.hasSuffix("LIMIT 1000 OFFSET 0"))
        XCTAssertFalse(outcome.sql.contains("-- LIMIT 5 LIMIT"))
    }

    func testIgnoresLimitInsideBlockComment() {
        let outcome = SQLAutoLimit.augment("SELECT * FROM t /* LIMIT 5 */", dialect: mysql)
        XCTAssertTrue(outcome.applied)
        XCTAssertTrue(outcome.sql.hasSuffix("LIMIT 1000 OFFSET 0"))
    }

    func testSkipsNonSelectStatements() {
        XCTAssertFalse(SQLAutoLimit.augment("UPDATE t SET x = 1 WHERE id = 1", dialect: mysql).applied)
        XCTAssertFalse(SQLAutoLimit.augment("DELETE FROM t WHERE id = 1", dialect: mysql).applied)
        XCTAssertFalse(SQLAutoLimit.augment("INSERT INTO t (id) VALUES (1)", dialect: mysql).applied)
    }

    func testSkipsDataModifyingCTE() {
        let outcome = SQLAutoLimit.augment(
            "WITH x AS (DELETE FROM t RETURNING id) SELECT * FROM x", dialect: postgres
        )
        XCTAssertFalse(outcome.applied)
    }

    func testSkipsMultipleStatements() {
        let outcome = SQLAutoLimit.augment("SELECT 1; SELECT 2", dialect: mysql)
        XCTAssertFalse(outcome.applied)
    }

    func testStripsTrailingSemicolonBeforeAppending() {
        let outcome = SQLAutoLimit.augment("SELECT * FROM users;", dialect: mysql)
        XCTAssertTrue(outcome.applied)
        XCTAssertEqual(outcome.sql, "SELECT * FROM users LIMIT 1000 OFFSET 0")
    }

    func testSkipsUnterminatedStringLiteral() {
        let outcome = SQLAutoLimit.augment("SELECT 'unterminated", dialect: mysql)
        XCTAssertFalse(outcome.applied)
    }

    func testSkipsFetchFirstPagination() {
        let outcome = SQLAutoLimit.augment(
            "SELECT * FROM t ORDER BY id FETCH FIRST 5 ROWS ONLY", dialect: postgres
        )
        XCTAssertFalse(outcome.applied)
    }

    func testSkipsExistingOffsetPagination() {
        let outcome = SQLAutoLimit.augment("SELECT * FROM t OFFSET 10", dialect: postgres)
        XCTAssertFalse(outcome.applied)
    }

    func testEqualityIgnoresTruncationMetadata() {
        let columns = [ColumnMeta(name: "id")]
        let rows: [[Cell]] = [[.int(1)]]
        let plain = QueryResult(columns: columns, rows: rows)
        let truncated = QueryResult(columns: columns, rows: rows, truncated: true, estimatedTotal: 99)
        XCTAssertEqual(plain, truncated)
    }

    func testEqualityStillComparesRows() {
        let columns = [ColumnMeta(name: "id")]
        let a = QueryResult(columns: columns, rows: [[.int(1)]])
        let b = QueryResult(columns: columns, rows: [[.int(2)]])
        XCTAssertNotEqual(a, b)
    }

    private final class ScriptedConnection: SessionConnection, @unchecked Sendable {
        let log: Log
        var live = true
        private let lock = NSLock()
        private var blocked: CheckedContinuation<QueryResult, Error>?

        init(log: Log) {
            self.log = log; log.opened()
        }

        var isLive: Bool {
            lock.lock(); defer { lock.unlock() }; return live
        }

        func useDatabase(_ database: String) async throws {
            log.used(database)
        }

        func runText(_ sql: String) async throws -> QueryResult {
            if sql == "block" {
                return try await withCheckedThrowingContinuation { continuation in
                    lock.lock(); blocked = continuation; lock.unlock()
                }
            }
            if sql == "fail" { throw DatabaseError.syntax("boom") }
            return QueryResult(columns: [ColumnMeta(name: sql)], rows: [])
        }

        func runSelect(_: DMLStatement) async throws -> QueryResult {
            QueryResult(columns: [], rows: [])
        }

        func shutdown() async {
            lock.lock()
            live = false
            let continuation = blocked
            blocked = nil
            lock.unlock()
            continuation?.resume(throwing: DatabaseError.connection("connection closed"))
        }
    }

    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var opens = 0
        private(set) var usedDatabases: [String] = []
        func opened() {
            lock.lock(); opens += 1; lock.unlock()
        }

        func used(_ database: String) {
            lock.lock(); usedDatabases.append(database); lock.unlock()
        }
    }

    private func makeSession(log: Log) -> ConnectionSession {
        ConnectionSession { ScriptedConnection(log: log) }
    }

    func testEmitsUseDatabaseOnFirstStatementAndOnlyWhenChanged() async throws {
        let log = Log()
        let session = makeSession(log: log)
        _ = try await session.runText("a", database: "analytics")
        _ = try await session.runText("b", database: "analytics")
        _ = try await session.runText("c", database: "reporting")
        XCTAssertEqual(log.usedDatabases, ["analytics", "reporting"])
    }

    func testCancelInFlightMapsToCancelledAndReconnects() async throws {
        let log = Log()
        let session = makeSession(log: log)

        let running = Task { try await session.runText("block", database: "analytics") }
        try await Task.sleep(for: .milliseconds(60))
        await session.cancelInFlight()

        do {
            _ = try await running.value
            XCTFail("cancelled query should throw")
        } catch {
            XCTAssertEqual(error as? DatabaseError, .cancelled)
        }

        _ = try await session.runText("after", database: "analytics")
        XCTAssertEqual(log.opens, 2)
        XCTAssertEqual(log.usedDatabases, ["analytics", "analytics"])
    }

    func testRealErrorAfterReconnectIsNotReportedAsCancelled() async throws {
        let log = Log()
        let session = makeSession(log: log)

        let running = Task { try await session.runText("block", database: "analytics") }
        try await Task.sleep(for: .milliseconds(60))
        await session.cancelInFlight()
        _ = try? await running.value

        let result = try await session.runText("ok", database: "analytics")
        XCTAssertEqual(result.columns.first?.name, "ok")
    }

    func testStaleCancelDoesNotMislabelLaterRealError() async throws {
        let log = Log()
        let session = makeSession(log: log)
        await session.cancelInFlight()
        do {
            _ = try await session.runText("fail", database: "analytics")
            XCTFail("a genuine error must not be reported as cancelled")
        } catch {
            XCTAssertEqual(error as? DatabaseError, .syntax("boom"))
        }
    }
}
