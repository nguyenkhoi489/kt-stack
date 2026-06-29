import XCTest
@testable import KTStackKit

final class SQLKeywordsTests: XCTestCase {
    func testCommonKeywordsPresentForEveryDialect() {
        for kind in [DatabaseKind.mysql, .postgres, .sqlite] {
            let words = SQLKeywords.forKind(kind)
            for expected in ["SELECT", "FROM", "WHERE", "LIMIT", "JOIN"] {
                XCTAssertTrue(words.contains(expected), "\(kind) missing \(expected)")
            }
        }
    }

    func testDialectSpecificKeywords() {
        XCTAssertTrue(SQLKeywords.forKind(.mysql).contains("AUTO_INCREMENT"))
        XCTAssertTrue(SQLKeywords.forKind(.postgres).contains("RETURNING"))
        XCTAssertTrue(SQLKeywords.forKind(.sqlite).contains("AUTOINCREMENT"))
    }

    func testKeywordsAreUppercaseAndDeduplicated() {
        let words = SQLKeywords.forKind(.mysql)
        XCTAssertEqual(words, words.map { $0.uppercased() })
        XCTAssertEqual(words.count, Set(words).count)
    }
}
