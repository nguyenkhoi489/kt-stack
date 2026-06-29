import XCTest
@testable import KTStackKit

@MainActor
final class DatabaseViewModelFetchMoreTests: XCTestCase {
    private final class FetchStub: RelationalDriver, @unchecked Sendable {
        let kind: DatabaseKind = .mysql
        var total: Int
        var paginateDelay: Duration = .zero
        var columnNameByTable: [String: String] = ["users": "id", "orders": "ref"]
        private(set) var paginateOffsets: [Int] = []

        init(total: Int) {
            self.total = total
        }

        func ping() async throws {}
        func listDatabases() async throws -> [DatabaseInfo] {
            [DatabaseInfo(name: "db")]
        }

        func listTables(database _: String) async throws -> [TableInfo] {
            [TableInfo(name: "users"), TableInfo(name: "orders")]
        }

        func columns(database _: String, table: String) async throws -> [ColumnInfo] {
            [ColumnInfo(
                name: columnNameByTable[table] ?? "id",
                dataType: "int",
                isNullable: false,
                isPrimaryKey: true
            )]
        }

        func indexes(database _: String, table _: String) async throws -> [IndexInfo] {
            []
        }

        func foreignKeys(database _: String) async throws -> [ForeignKeyRelation] {
            []
        }

        func query(_: String, database _: String?) async throws -> QueryResult {
            QueryResult(columns: [], rows: [])
        }

        func paginatedRows(
            database _: String,
            table: String,
            limit: Int,
            offset: Int
        ) async throws -> QueryResult {
            if paginateDelay > .zero { try? await Task.sleep(for: paginateDelay) }
            paginateOffsets.append(offset)
            let name = columnNameByTable[table] ?? "id"
            let end = min(offset + limit, total)
            let rows = (offset..<max(offset, end)).map { [Cell.int(Int64($0))] }
            return QueryResult(columns: [ColumnMeta(name: name)], rows: rows)
        }

        func openSession() async throws {}
        func closeSession() async {}
        func runSelect(_: DMLStatement, database _: String?) async throws -> QueryResult {
            QueryResult(columns: [], rows: [])
        }

        func insert(database _: String, table _: String, values _: [ColumnValue]) async throws {}
        func update(database _: String, table _: String, values _: [ColumnValue], key _: [ColumnValue]) async throws {}
        func delete(database _: String, table _: String, key _: [ColumnValue]) async throws {}
    }

    private func browse(
        _ driver: FetchStub,
        pageSize: Int,
        table: String = "users"
    ) async -> DatabaseViewModel {
        let vm = DatabaseViewModel(makeDriver: { _, _ in driver }, passwordFor: { _ in nil })
        vm.pageSize = pageSize
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db")
        await vm.select(table: TableInfo(name: table))
        return vm
    }

    func testLoadMoreAppendsRowsWithoutReplacingExisting() async {
        let vm = await browse(FetchStub(total: 500), pageSize: 100)
        XCTAssertEqual(vm.result?.rowCount, 100)

        await vm.loadMoreRows()
        XCTAssertEqual(vm.result?.rowCount, 200)
        XCTAssertEqual(vm.pageOffset, 100)
        XCTAssertTrue(vm.hasMorePages)
    }

    func testLoadMoreStopsAtEndOfData() async {
        let driver = FetchStub(total: 150)
        let vm = await browse(driver, pageSize: 100)

        await vm.loadMoreRows()
        XCTAssertEqual(vm.result?.rowCount, 150)
        XCTAssertFalse(vm.hasMorePages)

        let calls = driver.paginateOffsets.count
        await vm.loadMoreRows()
        XCTAssertEqual(driver.paginateOffsets.count, calls)
    }

    func testIsFetchingMoreTogglesAroundLoadMore() async {
        let driver = FetchStub(total: 500)
        driver.paginateDelay = .milliseconds(40)
        let vm = await browse(driver, pageSize: 100)

        async let inFlight: Void = vm.loadMoreRows()
        try? await Task.sleep(for: .milliseconds(12))
        XCTAssertTrue(vm.isFetchingMore)
        await inFlight
        XCTAssertFalse(vm.isFetchingMore)
    }

    func testDoesNotDoubleFetchWhileAlreadyFetching() async {
        let driver = FetchStub(total: 500)
        driver.paginateDelay = .milliseconds(50)
        let vm = await browse(driver, pageSize: 100)
        let before = driver.paginateOffsets.count

        async let first: Void = vm.loadMoreRows()
        try? await Task.sleep(for: .milliseconds(8))
        async let second: Void = vm.loadMoreRows()
        _ = await (first, second)

        XCTAssertEqual(driver.paginateOffsets.count, before + 1)
        XCTAssertEqual(vm.result?.rowCount, 200)
    }

    func testRowEditAfterScrollKeepsAllLoadedRows() async {
        let driver = FetchStub(total: 500)
        let vm = await browse(driver, pageSize: 100)
        await vm.loadMoreRows()
        XCTAssertEqual(vm.result?.rowCount, 200)

        await vm.updateRow(at: 0, values: [ColumnValue(column: "id", value: .int(0))])
        XCTAssertEqual(vm.result?.rowCount, 200)
        XCTAssertEqual(vm.pageOffset, 100)
        XCTAssertTrue(vm.hasMorePages)
    }

    func testRowEditWithoutScrollReloadsSinglePage() async {
        let driver = FetchStub(total: 500)
        let vm = await browse(driver, pageSize: 100)
        XCTAssertEqual(vm.result?.rowCount, 100)

        await vm.updateRow(at: 0, values: [ColumnValue(column: "id", value: .int(0))])
        XCTAssertEqual(vm.result?.rowCount, 100)
    }

    func testSwitchingTableMidPrefetchDropsTheStaleAppend() async {
        let driver = FetchStub(total: 500)
        driver.paginateDelay = .milliseconds(60)
        let vm = await browse(driver, pageSize: 100, table: "users")

        async let prefetch: Void = vm.loadMoreRows()
        try? await Task.sleep(for: .milliseconds(10))
        await vm.select(table: TableInfo(name: "orders"))
        await prefetch

        XCTAssertEqual(vm.selectedTable?.name, "orders")
        XCTAssertEqual(vm.result?.rowCount, 100)
        XCTAssertEqual(vm.result?.columns.first?.name, "ref")
    }
}
