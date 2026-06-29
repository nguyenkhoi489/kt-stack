import XCTest
@testable import KTStackKit

/// Engine-free coverage of the destructive-SQL confirm net — CI-blocking. Verifies it flags broad
/// mutations (keyless DELETE/UPDATE, DROP/TRUNCATE) and lets scoped statements through, including
/// across a multi-statement batch.
final class DestructiveGuardTests: XCTestCase {
    func testKeylessDeleteAndUpdateAreFlagged() {
        XCTAssertTrue(DestructiveGuard.evaluate("DELETE FROM users").isDestructive)
        XCTAssertTrue(DestructiveGuard.evaluate("UPDATE users SET active = 0").isDestructive)
    }

    func testScopedDeleteAndUpdateAreSafe() {
        XCTAssertFalse(DestructiveGuard.evaluate("DELETE FROM users WHERE id = 1").isDestructive)
        XCTAssertFalse(DestructiveGuard.evaluate("UPDATE users SET active = 0 WHERE id = 1").isDestructive)
    }

    func testDropAndTruncateAreFlagged() {
        XCTAssertTrue(DestructiveGuard.evaluate("DROP TABLE users").isDestructive)
        XCTAssertTrue(DestructiveGuard.evaluate("TRUNCATE TABLE users").isDestructive)
        // Even with a WHERE-looking tail, DROP is unconditionally destructive.
        XCTAssertTrue(DestructiveGuard.evaluate("DROP DATABASE app").isDestructive)
    }

    func testSelectAndInsertAreSafe() {
        XCTAssertFalse(DestructiveGuard.evaluate("SELECT * FROM users").isDestructive)
        XCTAssertFalse(DestructiveGuard.evaluate("INSERT INTO users (name) VALUES ('x')").isDestructive)
    }

    func testLeadingWhitespaceAndCaseInsensitive() {
        XCTAssertTrue(DestructiveGuard.evaluate("  \n delete from t").isDestructive)
        XCTAssertTrue(DestructiveGuard.evaluate("\tDrOp TaBlE t").isDestructive)
    }

    func testAnyDestructiveStatementInBatchFlagsWholeBatch() {
        let verdict = DestructiveGuard.evaluate("UPDATE t SET a = 1 WHERE id = 1; DELETE FROM t")
        XCTAssertTrue(verdict.isDestructive)
        XCTAssertNotNil(verdict.reason)
    }

    func testReasonIsNilWhenSafe() {
        XCTAssertNil(DestructiveGuard.evaluate("SELECT 1").reason)
    }
}
