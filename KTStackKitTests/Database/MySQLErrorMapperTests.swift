import NIOCore
import XCTest
@testable import KTStackKit

/// Engine-free coverage of the MySQL error/literal helpers — CI-blocking. `quoteLiteral` is a security
/// boundary alongside `quoteIdent`: schema/table names land in `information_schema` filters as string
/// literals, so it must doubly-escape quotes/backslashes and reject NUL. The refused-connection
/// classification decides whether the UI says "engine down" vs a generic connection error.
final class MySQLErrorMapperTests: XCTestCase {
    func testQuoteLiteralWrapsAndDoublesSingleQuotes() throws {
        XCTAssertEqual(try MySQLErrorMapper.quoteLiteral("app"), "'app'")
        // An embedded quote is doubled so O'Brien can't break out of the literal.
        XCTAssertEqual(try MySQLErrorMapper.quoteLiteral("O'Brien"), "'O''Brien'")
    }

    func testQuoteLiteralEscapesBackslash() throws {
        XCTAssertEqual(try MySQLErrorMapper.quoteLiteral("a\\b"), "'a\\\\b'")
    }

    func testQuoteLiteralRejectsNul() {
        // NUL can truncate at the server's C-string boundary, so it's refused rather than escaped.
        XCTAssertThrowsError(try MySQLErrorMapper.quoteLiteral("a\u{0}b"))
    }

    func testRefusedSocketMapsToEngineNotRunningWhenManaged() {
        let refused = IOError(errnoCode: ECONNREFUSED, reason: "refused")
        guard case .engineNotRunning = MySQLErrorMapper.map(refused, isManaged: true) else {
            return XCTFail("managed refused socket should surface engineNotRunning")
        }
    }

    func testRefusedSocketMapsToGenericConnectionWhenExternal() {
        let refused = IOError(errnoCode: ECONNREFUSED, reason: "refused")
        guard case .connection = MySQLErrorMapper.map(refused, isManaged: false) else {
            return XCTFail("external refused socket should surface a generic connection error")
        }
    }

    func testAlreadyTypedErrorPassesThrough() {
        let typed = DatabaseError.engineNotInstalled(kind: "MySQL")
        guard case .engineNotInstalled = MySQLErrorMapper.map(typed, isManaged: true) else {
            return XCTFail("a DatabaseError should map to itself")
        }
    }
}
