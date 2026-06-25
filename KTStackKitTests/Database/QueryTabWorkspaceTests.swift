import XCTest
@testable import KTStackKit

@MainActor
final class QueryTabWorkspaceTests: XCTestCase {
    private final class StubDriver: RelationalDriver, @unchecked Sendable {
        let kind: DatabaseKind = .mysql
        var queryDelay: Duration = .zero
        private(set) var queryCalls: [(sql: String, database: String?)] = []

        func ping() async throws {}
        func listDatabases() async throws -> [DatabaseInfo] { [DatabaseInfo(name: "app")] }
        func listTables(database: String) async throws -> [TableInfo] { [TableInfo(name: "users")] }
        func columns(database: String, table: String) async throws -> [ColumnInfo] { [] }
        func indexes(database: String, table: String) async throws -> [IndexInfo] { [] }
        func foreignKeys(database: String) async throws -> [ForeignKeyRelation] { [] }

        func query(_ sql: String, database: String?) async throws -> QueryResult {
            if queryDelay > .zero { try? await Task.sleep(for: queryDelay) }
            queryCalls.append((sql, database))
            return QueryResult(columns: [ColumnMeta(name: "sql")], rows: [[.text(sql)]])
        }

        func paginatedRows(database: String, table: String, limit: Int, offset: Int) async throws -> QueryResult {
            QueryResult(columns: [ColumnMeta(name: "id")], rows: [[.int(1)]])
        }

        func openSession() async throws {}
        func closeSession() async {}
        func runSelect(_ statement: DMLStatement, database: String?) async throws -> QueryResult {
            QueryResult(columns: [], rows: [])
        }

        func insert(database: String, table: String, values: [ColumnValue]) async throws {}
        func update(database: String, table: String, values: [ColumnValue], key: [ColumnValue]) async throws {}
        func delete(database: String, table: String, key: [ColumnValue]) async throws {}
    }

    private func temporaryHistoryStore() -> QueryHistoryStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-query-tabs-\(UUID().uuidString)", isDirectory: true)
        return QueryHistoryStore(paths: AppSupportPaths(root: root))
    }

    private func makeVM(_ driver: StubDriver) -> DatabaseViewModel {
        DatabaseViewModel(makeDriver: { _, _ in driver },
                          passwordFor: { _ in nil },
                          historyStore: temporaryHistoryStore())
    }

    func testQueryTabsKeepSQLAndResultsIsolated() async {
        let driver = StubDriver()
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        let firstID = try! XCTUnwrap(vm.activeQueryTab?.id)

        vm.updateActiveQuerySQL("SELECT 1")
        await vm.runActiveQueryTab()
        vm.addQueryTab()
        let secondID = try! XCTUnwrap(vm.activeQueryTab?.id)
        vm.updateActiveQuerySQL("SELECT 2")
        await vm.runActiveQueryTab()

        let dialect = SQLDialect.forKind(.mysql)
        let sent1 = SQLAutoLimit.augment("SELECT 1", dialect: dialect).sql
        let sent2 = SQLAutoLimit.augment("SELECT 2", dialect: dialect).sql
        let first = try! XCTUnwrap(vm.queryTabs.first { $0.id == firstID })
        let second = try! XCTUnwrap(vm.queryTabs.first { $0.id == secondID })
        XCTAssertEqual(first.sql, "SELECT 1")
        XCTAssertEqual(first.result?.rows.first?.first, .text(sent1))
        XCTAssertEqual(second.sql, "SELECT 2")
        XCTAssertEqual(second.result?.rows.first?.first, .text(sent2))
        XCTAssertEqual(driver.queryCalls.map(\.sql), [sent1, sent2])
    }

    func testClosingLastTabLeavesOneEmptyTab() {
        let vm = makeVM(StubDriver())
        let id = try! XCTUnwrap(vm.activeQueryTab?.id)

        vm.closeQueryTab(id)

        XCTAssertEqual(vm.queryTabs.count, 1)
        XCTAssertEqual(vm.activeQueryTab?.sql, "SELECT 1")
        XCTAssertEqual(vm.activeQueryTab?.title, "Query 1")
    }

    func testTableBrowseDoesNotRecordQueryHistory() async {
        let vm = makeVM(StubDriver())
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "app")
        await vm.select(table: TableInfo(name: "users"))

        XCTAssertTrue(vm.queryHistoryEntries.isEmpty)
        XCTAssertTrue(vm.isTableBrowse)
    }

    func testSwitchingQueryTabsDoesNotClearTableBrowseResult() async {
        let vm = makeVM(StubDriver())
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "app")
        await vm.select(table: TableInfo(name: "users"))

        XCTAssertTrue(vm.isTableBrowse)
        XCTAssertEqual(vm.result?.rows.first?.first, .int(1))

        let firstID = try! XCTUnwrap(vm.activeQueryTab?.id)
        vm.addQueryTab()
        vm.selectQueryTab(firstID)

        XCTAssertTrue(vm.isTableBrowse)
        XCTAssertEqual(vm.result?.rows.first?.first, .int(1))
    }

    func testFinishingQueryTabDoesNotOverwriteTableBrowseResult() async {
        let driver = StubDriver()
        driver.queryDelay = .milliseconds(80)
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "app")
        vm.updateActiveQuerySQL("SELECT delayed")

        async let query: Void = vm.runActiveQueryTab()
        try? await Task.sleep(for: .milliseconds(10))
        await vm.select(table: TableInfo(name: "users"))
        await query

        let sent = SQLAutoLimit.augment("SELECT delayed", dialect: SQLDialect.forKind(.mysql)).sql
        XCTAssertTrue(vm.isTableBrowse)
        XCTAssertEqual(vm.result?.rows.first?.first, .int(1))
        XCTAssertEqual(vm.activeQueryTab?.result?.rows.first?.first, .text(sent))
    }

    func testRunSQLRecordsHistoryWithoutUsingQueryTabResult() async {
        let vm = makeVM(StubDriver())
        await vm.select(profile: .managedMySQL)

        await vm.runSQL("SELECT legacy")

        let sent = SQLAutoLimit.augment("SELECT legacy", dialect: SQLDialect.forKind(.mysql)).sql
        XCTAssertEqual(vm.result?.rows.first?.first, .text(sent))
        XCTAssertNil(vm.activeQueryTab?.result)
        XCTAssertEqual(vm.queryHistoryEntries.map(\.sql), ["SELECT legacy"])
    }

    func testConfirmedDestructiveActiveTabRunsInActiveTab() async {
        let driver = StubDriver()
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        vm.updateActiveQuerySQL("DELETE FROM users")

        await vm.runActiveQueryTab()
        XCTAssertEqual(vm.pendingDangerousSQL, "DELETE FROM users")

        await vm.runActiveQueryTab(confirmed: true)
        XCTAssertNil(vm.pendingDangerousSQL)
        XCTAssertEqual(vm.activeQueryTab?.result?.rows.first?.first, .text("DELETE FROM users"))
        XCTAssertEqual(driver.queryCalls.map(\.sql), ["DELETE FROM users"])
    }
}
