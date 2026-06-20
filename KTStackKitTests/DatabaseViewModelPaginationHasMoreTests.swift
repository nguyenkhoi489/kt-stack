import XCTest
@testable import KTStackKit

@MainActor
final class DatabaseViewModelPaginationHasMoreTests: XCTestCase {

    private final class FiniteDataStub: RelationalDriver, @unchecked Sendable {
        let kind: DatabaseKind = .mysql
        let total: Int
        private(set) var requestedLimits: [Int] = []

        init(total: Int) { self.total = total }

        func ping() async throws {}
        func listDatabases() async throws -> [DatabaseInfo] { [DatabaseInfo(name: "db")] }
        func listTables(database: String) async throws -> [TableInfo] { [TableInfo(name: "t")] }
        func columns(database: String, table: String) async throws -> [ColumnInfo] {
            [ColumnInfo(name: "id", dataType: "int", isNullable: false, isPrimaryKey: true)]
        }
        func indexes(database: String, table: String) async throws -> [IndexInfo] { [] }
        func foreignKeys(database: String) async throws -> [ForeignKeyRelation] { [] }
        func query(_ sql: String, database: String?) async throws -> QueryResult {
            QueryResult(columns: [], rows: [])
        }

        func paginatedRows(database: String, table: String,
                           limit: Int, offset: Int) async throws -> QueryResult {
            requestedLimits.append(limit)
            let end = min(offset + limit, total)
            let rows = (offset..<max(offset, end)).map { [Cell.int(Int64($0))] }
            return QueryResult(columns: [ColumnMeta(name: "id")], rows: rows)
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

    private func browse(total: Int, pageSize: Int) async -> (DatabaseViewModel, FiniteDataStub) {
        let driver = FiniteDataStub(total: total)
        let vm = DatabaseViewModel(makeDriver: { _, _ in driver }, passwordFor: { _ in nil })
        vm.pageSize = pageSize
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db")
        await vm.select(table: TableInfo(name: "t"))
        return (vm, driver)
    }

    func testFetchesOneExtraRowToProbeForMorePages() async {
        let (_, driver) = await browse(total: 500, pageSize: 100)
        XCTAssertEqual(driver.requestedLimits.first, 101)
    }

    func testExactMultipleDoesNotReportAPhantomNextPage() async {
        let (vm, _) = await browse(total: 100, pageSize: 100)
        XCTAssertEqual(vm.result?.rowCount, 100)
        XCTAssertFalse(vm.hasMorePages)
    }

    func testLastFullPageOfAMultipleLeavesNoBlankPage() async {
        let (vm, _) = await browse(total: 200, pageSize: 100)
        XCTAssertTrue(vm.hasMorePages)

        await vm.nextPage()
        XCTAssertEqual(vm.pageOffset, 100)
        XCTAssertEqual(vm.result?.rowCount, 100)
        XCTAssertFalse(vm.hasMorePages)
    }

    func testPartialFinalPageReportsNoMore() async {
        let (vm, _) = await browse(total: 150, pageSize: 100)
        XCTAssertTrue(vm.hasMorePages)

        await vm.nextPage()
        XCTAssertEqual(vm.result?.rowCount, 50)
        XCTAssertFalse(vm.hasMorePages)
    }

    func testPageNeverShowsTheProbeRow() async {
        let (vm, _) = await browse(total: 500, pageSize: 100)
        XCTAssertEqual(vm.result?.rowCount, 100)
        XCTAssertTrue(vm.hasMorePages)
    }
}
