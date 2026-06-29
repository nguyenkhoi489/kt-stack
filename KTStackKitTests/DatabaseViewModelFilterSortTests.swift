import XCTest
@testable import KTStackKit

@MainActor
final class DatabaseViewModelFilterSortTests: XCTestCase {
    private final class FilterStub: RelationalDriver, @unchecked Sendable {
        let kind: DatabaseKind = .mysql
        private(set) var runSelectCalls: [DMLStatement] = []
        private(set) var paginateCalls = 0

        func ping() async throws {}
        func listDatabases() async throws -> [DatabaseInfo] {
            [DatabaseInfo(name: "db")]
        }

        func listTables(database _: String) async throws -> [TableInfo] {
            [TableInfo(name: "users")]
        }

        func columns(database _: String, table _: String) async throws -> [ColumnInfo] {
            [
                ColumnInfo(name: "id", dataType: "int", isNullable: false, isPrimaryKey: true),
                ColumnInfo(name: "name", dataType: "text", isNullable: true, isPrimaryKey: false),
                ColumnInfo(name: "age", dataType: "int", isNullable: true, isPrimaryKey: false),
            ]
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
            table _: String,
            limit _: Int,
            offset _: Int
        ) async throws -> QueryResult {
            paginateCalls += 1
            return QueryResult(columns: [ColumnMeta(name: "id")], rows: [[.int(1)], [.int(2)]])
        }

        func openSession() async throws {}
        func closeSession() async {}
        func runSelect(_ statement: DMLStatement, database _: String?) async throws -> QueryResult {
            runSelectCalls.append(statement)
            return QueryResult(columns: [ColumnMeta(name: "id")], rows: [[.int(1)]])
        }

        func insert(database _: String, table _: String, values _: [ColumnValue]) async throws {}
        func update(database _: String, table _: String, values _: [ColumnValue], key _: [ColumnValue]) async throws {}
        func delete(database _: String, table _: String, key _: [ColumnValue]) async throws {}
    }

    private func browse(_ driver: FilterStub) async -> DatabaseViewModel {
        let vm = DatabaseViewModel(makeDriver: { _, _ in driver }, passwordFor: { _ in nil })
        vm.pageSize = 100
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db")
        await vm.select(table: TableInfo(name: "users"))
        return vm
    }

    func testApplyFilterIssuesBoundRunSelect() async {
        let driver = FilterStub()
        let vm = await browse(driver)
        await vm.applyFilters([FilterCondition(column: "name", op: .equals, value: .text("ann"))])

        XCTAssertEqual(vm.activeFilters.count, 1)
        XCTAssertEqual(vm.pageOffset, 0)
        let stmt = driver.runSelectCalls.last
        XCTAssertEqual(stmt?.sql, "SELECT * FROM `db`.`users` WHERE `name` = ? LIMIT 101 OFFSET 0")
        XCTAssertEqual(stmt?.binds, [.text("ann")])
    }

    func testApplySortOrdersServerSideAndResetsOffset() async {
        let driver = FilterStub()
        let vm = await browse(driver)
        await vm.applySort(SortSpec(column: "age", ascending: false))

        XCTAssertEqual(vm.activeSort, SortSpec(column: "age", ascending: false))
        XCTAssertEqual(vm.pageOffset, 0)
        XCTAssertEqual(
            driver.runSelectCalls.last?.sql,
            "SELECT * FROM `db`.`users` ORDER BY `age` DESC LIMIT 101 OFFSET 0"
        )
    }

    func testToggleSortCyclesAscendingDescendingThenOff() async {
        let driver = FilterStub()
        let vm = await browse(driver)

        await vm.toggleSort(column: "name")
        XCTAssertEqual(vm.activeSort, SortSpec(column: "name", ascending: true))
        await vm.toggleSort(column: "name")
        XCTAssertEqual(vm.activeSort, SortSpec(column: "name", ascending: false))
        await vm.toggleSort(column: "name")
        XCTAssertNil(vm.activeSort)
    }

    func testClearReturnsToUnfilteredPaginatedRows() async {
        let driver = FilterStub()
        let vm = await browse(driver)
        await vm.applyFilters([FilterCondition(column: "name", op: .equals, value: .text("ann"))])
        let paginatesBefore = driver.paginateCalls

        await vm.clearFiltersAndSort()
        XCTAssertTrue(vm.activeFilters.isEmpty)
        XCTAssertNil(vm.activeSort)
        XCTAssertEqual(driver.paginateCalls, paginatesBefore + 1)
    }

    func testUnknownColumnIsRejectedByAllowList() async {
        let driver = FilterStub()
        let vm = await browse(driver)

        await vm.applyFilters([FilterCondition(column: "ghost", op: .equals, value: .text("x"))])
        XCTAssertTrue(vm.activeFilters.isEmpty)

        await vm.applySort(SortSpec(column: "ghost", ascending: true))
        XCTAssertNil(vm.activeSort)
    }

    func testFilterValueIsBoundNotInterpolated() async {
        let driver = FilterStub()
        let vm = await browse(driver)
        let evil = "x'; DROP TABLE users;--"
        await vm.applyFilters([FilterCondition(column: "name", op: .equals, value: .text(evil))])

        let stmt = driver.runSelectCalls.last
        XCTAssertFalse(stmt?.sql.contains("DROP") ?? true)
        XCTAssertEqual(stmt?.binds, [.text(evil)])
    }
}
