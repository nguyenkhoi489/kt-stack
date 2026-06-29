import XCTest
@testable import KTStackKit

final class SQLCompletionEngineTests: XCTestCase {
    private let catalog = SchemaCatalog(
        tables: ["users", "orders"],
        columnsByTable: [
            "users": ["id", "name", "email"],
            "orders": ["id", "user_id", "total"],
        ]
    )

    private let keywords = SQLKeywords.forKind(.mysql)

    private func complete(
        _ text: String,
        caret: Int? = nil,
        catalog: SchemaCatalog? = nil
    ) -> [SQLCompletionItem] {
        SQLCompletionEngine.completions(
            text: text, caret: caret ?? text.count,
            catalog: catalog ?? self.catalog, keywords: keywords
        )
    }

    func testKeywordPrefixMatch() {
        let items = complete("sel")
        XCTAssertEqual(items.first?.text, "SELECT")
        XCTAssertTrue(items.allSatisfy { $0.text.lowercased().contains("sel") })
    }

    func testTablePrefixMatch() {
        let texts = complete("SELECT * FROM u").map(\.text)
        XCTAssertTrue(texts.contains("users"))
        XCTAssertFalse(texts.contains("orders"))
    }

    func testQualifiedColumnsRestrictToAliasTable() {
        let prefix = "SELECT u."
        let items = complete(prefix + " FROM users u", caret: prefix.count)
        XCTAssertEqual(Set(items.map(\.text)), ["id", "name", "email"])
        XCTAssertTrue(items.allSatisfy { $0.kind == .column })
    }

    func testQualifiedColumnsWithPartialFilter() {
        let prefix = "SELECT * FROM users u WHERE u.na"
        let items = complete(prefix)
        XCTAssertEqual(items.map(\.text), ["name"])
    }

    func testBareColumnGathersFromTablesAndDedupes() {
        let prefix = "SELECT i"
        let items = complete(prefix + " FROM users u JOIN orders o", caret: prefix.count)
        let texts = items.map(\.text)
        XCTAssertEqual(texts.filter { $0 == "id" }.count, 1)
        XCTAssertTrue(texts.contains("id"))
        XCTAssertTrue(texts.contains { keywords.contains($0) })
    }

    func testPrefixMatchesRankAboveContainsMatches() {
        let items = complete("e")
        let endIndex = items.firstIndex { $0.text == "END" }
        let selectIndex = items.firstIndex { $0.text == "SELECT" }
        XCTAssertNotNil(endIndex)
        XCTAssertNotNil(selectIndex)
        XCTAssertLessThan(endIndex!, selectIndex!)
    }

    func testResultIsCappedAtFifty() {
        let many = (0..<80).map { "acol\($0)" }
        let big = SchemaCatalog(tables: ["t"], columnsByTable: ["t": many])
        let items = SQLCompletionEngine.completions(
            text: "a", caret: 1, catalog: big, keywords: []
        )
        XCTAssertLessThanOrEqual(items.count, 50)
    }

    func testEmptyWordWithoutQualifierReturnsNothing() {
        let prefix = "SELECT "
        let items = complete(prefix + " FROM users", caret: prefix.count)
        XCTAssertTrue(items.isEmpty)
    }

    func testQuotedIdentifierDoesNotCrash() {
        _ = complete("SELECT `i")
        _ = complete("SELECT \"i")
    }
}
