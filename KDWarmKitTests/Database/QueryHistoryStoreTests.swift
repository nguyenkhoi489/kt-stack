import XCTest
@testable import KDWarmKit

@MainActor
final class QueryHistoryStoreTests: XCTestCase {
    private func temporaryPaths() -> AppSupportPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kdwarm-query-history-\(UUID().uuidString)", isDirectory: true)
        return AppSupportPaths(root: root)
    }

    func testRecordPersistsNewestFirst() throws {
        let paths = temporaryPaths()
        let store = QueryHistoryStore(paths: paths, limit: 500)

        try store.record(sql: "SELECT 1", connectionLabel: "Local", database: "app")
        try store.record(sql: "SELECT 2", connectionLabel: "Local", database: "app")

        let reloaded = QueryHistoryStore(paths: paths, limit: 500)
        XCTAssertEqual(reloaded.entries().map(\.sql), ["SELECT 2", "SELECT 1"])
        XCTAssertEqual(reloaded.entries().first?.connectionLabel, "Local")
        XCTAssertEqual(reloaded.entries().first?.database, "app")
    }

    func testRecordDeduplicatesConsecutiveMatchingEntries() throws {
        let store = QueryHistoryStore(paths: temporaryPaths(), limit: 500)

        try store.record(sql: " SELECT 1\n", connectionLabel: "Local", database: "app")
        try store.record(sql: "SELECT 1", connectionLabel: "Local", database: "app")
        try store.record(sql: "SELECT 1", connectionLabel: "Other", database: "app")

        XCTAssertEqual(store.entries().map(\.connectionLabel), ["Other", "Local"])
        XCTAssertEqual(store.entries().map(\.sql), ["SELECT 1", "SELECT 1"])
    }

    func testRecordCapsOldEntries() throws {
        let store = QueryHistoryStore(paths: temporaryPaths(), limit: 2)

        try store.record(sql: "SELECT 1", connectionLabel: "Local", database: nil)
        try store.record(sql: "SELECT 2", connectionLabel: "Local", database: nil)
        try store.record(sql: "SELECT 3", connectionLabel: "Local", database: nil)

        XCTAssertEqual(store.entries().map(\.sql), ["SELECT 3", "SELECT 2"])
    }

    func testClearRemovesPersistedEntries() throws {
        let paths = temporaryPaths()
        let store = QueryHistoryStore(paths: paths, limit: 500)

        try store.record(sql: "SELECT 1", connectionLabel: "Local", database: nil)
        try store.clear()

        XCTAssertTrue(store.entries().isEmpty)
        XCTAssertTrue(QueryHistoryStore(paths: paths).entries().isEmpty)
    }
}
