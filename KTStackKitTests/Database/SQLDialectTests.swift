import XCTest
@testable import KTStackKit

/// Engine-free coverage of SQL composition — CI-blocking. The escaping rules here are a security
/// boundary: identifiers can't be bound parameters, so `quoteIdent` is the only thing standing
/// between an introspected table/column name and identifier injection. Pagination SQL is pure string
/// composition, proven without a server.
final class SQLDialectTests: XCTestCase {
    func testMySQLQuotesWithBackticksAndDoublesEmbedded() throws {
        let d = SQLDialect.forKind(.mysql)
        XCTAssertEqual(try d.quoteIdent("users"), "`users`")
        // An embedded backtick is doubled, so `tab`le` can't break out of the quoted identifier.
        XCTAssertEqual(try d.quoteIdent("tab`le"), "`tab``le`")
    }

    func testPostgresAndSQLiteQuoteWithDoubleQuotesAndDoubleEmbedded() throws {
        for kind in [DatabaseKind.postgres, .sqlite] {
            let d = SQLDialect.forKind(kind)
            XCTAssertEqual(try d.quoteIdent("col"), "\"col\"")
            XCTAssertEqual(try d.quoteIdent("we\"ird"), "\"we\"\"ird\"")
        }
    }

    func testQuoteIdentRejectsNulAndNewline() {
        let d = SQLDialect.forKind(.mysql)
        XCTAssertThrowsError(try d.quoteIdent("a\u{0}b")) // NUL can't be escaped by doubling
        XCTAssertThrowsError(try d.quoteIdent("a\nb")) // newline
        XCTAssertThrowsError(try d.quoteIdent("")) // empty identifier is meaningless
    }

    func testPaginateAppendsLimitOffset() {
        let d = SQLDialect.forKind(.mysql)
        XCTAssertEqual(
            d.paginate("SELECT * FROM `t`", limit: 50, offset: 0),
            "SELECT * FROM `t` LIMIT 50 OFFSET 0"
        )
        XCTAssertEqual(
            d.paginate("SELECT * FROM `t`", limit: 25, offset: 100),
            "SELECT * FROM `t` LIMIT 25 OFFSET 100"
        )
    }

    func testPaginateClampsNonPositiveLimitAndNegativeOffset() {
        let d = SQLDialect.forKind(.mysql)
        // A non-positive limit would be a malformed/secretly-unbounded query — clamp to 1.
        XCTAssertEqual(
            d.paginate("SELECT 1", limit: 0, offset: -5),
            "SELECT 1 LIMIT 1 OFFSET 0"
        )
    }

    func testQualifiedNameQuotesBothParts() throws {
        let d = SQLDialect.forKind(.mysql)
        XCTAssertEqual(try d.qualifiedTable(schema: "app", table: "users"), "`app`.`users`")
    }
}
