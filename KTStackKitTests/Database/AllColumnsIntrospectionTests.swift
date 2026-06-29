import XCTest
@testable import KTStackKit

final class AllColumnsIntrospectionTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-allcols-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeDriver() -> SQLiteDriver {
        let path = tempDir.appendingPathComponent("test.db").path
        let profile = ConnectionProfile(
            name: "t",
            kind: .sqlite,
            host: "",
            port: 0,
            user: "",
            database: SQLiteDriver.mainDatabase,
            filePath: path,
            readOnly: false
        )
        return SQLiteDriver(profile: profile)
    }

    func testAllColumnsMapsEveryTableToItsColumnsInOrder() async throws {
        let driver = makeDriver()
        _ = try await driver.query(
            "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)", database: nil
        )
        _ = try await driver.query(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, total REAL)", database: nil
        )

        let map = try await driver.allColumns(database: "main")

        XCTAssertEqual(map["users"], ["id", "name", "email"])
        XCTAssertEqual(map["orders"], ["id", "user_id", "total"])
    }

    func testAllColumnsIsEmptyForSchemaWithoutTables() async throws {
        let driver = makeDriver()
        _ = try await driver.query("SELECT 1", database: nil)
        let map = try await driver.allColumns(database: "main")
        XCTAssertTrue(map.isEmpty)
    }
}
