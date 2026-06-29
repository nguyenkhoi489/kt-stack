import XCTest
@testable import KTStackKit

final class SchemaCatalogTests: XCTestCase {
    private let catalog = SchemaCatalog(
        tables: ["Users", "orders"],
        columnsByTable: ["Users": ["id", "name"], "orders": ["id", "total"]]
    )

    func testColumnsLookupIsCaseInsensitive() {
        XCTAssertEqual(catalog.columns(of: "Users"), ["id", "name"])
        XCTAssertEqual(catalog.columns(of: "users"), ["id", "name"])
        XCTAssertEqual(catalog.columns(of: "ORDERS"), ["id", "total"])
        XCTAssertEqual(catalog.columns(of: "missing"), [])
    }

    func testAllColumnNamesDedupesCaseInsensitively() {
        XCTAssertEqual(catalog.allColumnNames, ["id", "name", "total"])
    }

    func testEmptyCatalogHasNoColumns() {
        XCTAssertTrue(SchemaCatalog.empty.allColumnNames.isEmpty)
        XCTAssertEqual(SchemaCatalog.empty.columns(of: "x"), [])
    }
}
