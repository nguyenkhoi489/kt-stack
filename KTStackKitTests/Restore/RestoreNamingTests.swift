import XCTest
@testable import KTStackKit

final class RestoreNamingTests: XCTestCase {
    func testLabelSlug() {
        XCTAssertEqual(RestoreNaming.label(from: "Nadestore VN"), "nadestore-vn")
        XCTAssertEqual(RestoreNaming.label(from: "1985 Blender!!"), "1985-blender")
        XCTAssertEqual(RestoreNaming.label(from: "  ---  "), "site")
    }

    func testDatabaseBase() {
        XCTAssertEqual(RestoreNaming.databaseBase(from: "nadestore-vn"), "nadestore_vn")
        XCTAssertEqual(RestoreNaming.databaseBase(from: "1985-blender"), "1985_blender")
    }

    func testUniqueNameTakesBaseWhenFree() async throws {
        let name = try await RestoreNaming.uniqueName(base: "shop") { _ in false }
        XCTAssertEqual(name, "shop")
    }

    func testUniqueNameSuffixesOnCollision() async throws {
        let taken: Set<String> = ["shop", "shop_2", "shop_3"]
        let name = try await RestoreNaming.uniqueName(base: "shop") { taken.contains($0) }
        XCTAssertEqual(name, "shop_4")
    }
}
