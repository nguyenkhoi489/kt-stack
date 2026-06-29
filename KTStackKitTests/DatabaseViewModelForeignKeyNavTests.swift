import XCTest
@testable import KTStackKit

@MainActor
final class DatabaseViewModelForeignKeyNavTests: XCTestCase {
    private final class FKStub: RelationalDriver, @unchecked Sendable {
        let kind: DatabaseKind = .mysql
        private(set) var runSelectCalls: [DMLStatement] = []

        func ping() async throws {}
        func listDatabases() async throws -> [DatabaseInfo] {
            [DatabaseInfo(name: "db")]
        }

        func listTables(database _: String) async throws -> [TableInfo] {
            [TableInfo(name: "orders"), TableInfo(name: "customers"), TableInfo(name: "other")]
        }

        func columns(database _: String, table: String) async throws -> [ColumnInfo] {
            switch table {
            case "customers":
                [
                    ColumnInfo(name: "id", dataType: "int", isNullable: false, isPrimaryKey: true),
                    ColumnInfo(name: "name", dataType: "text", isNullable: true, isPrimaryKey: false),
                ]
            default:
                [
                    ColumnInfo(name: "id", dataType: "int", isNullable: false, isPrimaryKey: true),
                    ColumnInfo(name: "user_id", dataType: "int", isNullable: true, isPrimaryKey: false),
                    ColumnInfo(name: "a", dataType: "int", isNullable: true, isPrimaryKey: false),
                    ColumnInfo(name: "b", dataType: "int", isNullable: true, isPrimaryKey: false),
                    ColumnInfo(name: "z", dataType: "int", isNullable: true, isPrimaryKey: false),
                ]
            }
        }

        func indexes(database _: String, table _: String) async throws -> [IndexInfo] {
            []
        }

        func foreignKeys(database _: String) async throws -> [ForeignKeyRelation] {
            [
                ForeignKeyRelation(
                    fromTable: "orders",
                    fromColumn: "user_id",
                    toTable: "customers",
                    toColumn: "id",
                    constraintName: "fk_user"
                ),
                ForeignKeyRelation(
                    fromTable: "orders",
                    fromColumn: "a",
                    toTable: "other",
                    toColumn: "x",
                    constraintName: "fk_composite"
                ),
                ForeignKeyRelation(
                    fromTable: "orders",
                    fromColumn: "b",
                    toTable: "other",
                    toColumn: "y",
                    constraintName: "fk_composite"
                ),
                ForeignKeyRelation(
                    fromTable: "orders",
                    fromColumn: "z",
                    toTable: "external",
                    toColumn: "id",
                    constraintName: "fk_cross"
                ),
            ]
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
            QueryResult(columns: [ColumnMeta(name: "id")], rows: [[.int(1)]])
        }

        func openSession() async throws {}
        func closeSession() async {}
        func runSelect(_ statement: DMLStatement, database _: String?) async throws -> QueryResult {
            runSelectCalls.append(statement)
            return QueryResult(columns: [ColumnMeta(name: "id")], rows: [[.int(42)]])
        }

        func insert(database _: String, table _: String, values _: [ColumnValue]) async throws {}
        func update(database _: String, table _: String, values _: [ColumnValue], key _: [ColumnValue]) async throws {}
        func delete(database _: String, table _: String, key _: [ColumnValue]) async throws {}
    }

    private func browseOrders(_ driver: FKStub) async -> DatabaseViewModel {
        let vm = DatabaseViewModel(makeDriver: { _, _ in driver }, passwordFor: { _ in nil })
        vm.pageSize = 100
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db")
        await vm.select(table: TableInfo(name: "orders"))
        await vm.loadRelationsIfNeeded()
        return vm
    }

    func testOnlySingleColumnSameSchemaForeignKeysAreNavigable() async {
        let vm = await browseOrders(FKStub())
        let fks = vm.navigableForeignKeys(forTable: "orders")
        XCTAssertEqual(Set(fks.keys), ["user_id"])
        XCTAssertEqual(fks["user_id"]?.toTable, "customers")
    }

    func testNavigateForeignKeySwitchesTableWithBoundFilterAndPushesBreadcrumb() async {
        let driver = FKStub()
        let vm = await browseOrders(driver)
        await vm.navigateForeignKey(fromColumn: "user_id", value: .int(42))

        XCTAssertEqual(vm.selectedTable?.name, "customers")
        XCTAssertEqual(vm.navigationStack.count, 1)
        XCTAssertEqual(vm.navigationStack.first?.table.name, "orders")
        XCTAssertEqual(vm.activeFilters, [FilterCondition(column: "id", op: .equals, value: .int(42))])
        let stmt = driver.runSelectCalls.last
        XCTAssertEqual(stmt?.sql, "SELECT * FROM `db`.`customers` WHERE `id` = ? LIMIT 101 OFFSET 0")
        XCTAssertEqual(stmt?.binds, [.int(42)])
    }

    func testPopNavigationRestoresPreviousTable() async {
        let vm = await browseOrders(FKStub())
        await vm.navigateForeignKey(fromColumn: "user_id", value: .int(42))
        await vm.popNavigation()

        XCTAssertEqual(vm.selectedTable?.name, "orders")
        XCTAssertTrue(vm.navigationStack.isEmpty)
        XCTAssertTrue(vm.activeFilters.isEmpty)
    }

    func testCompositeForeignKeyIsSuppressed() async {
        let vm = await browseOrders(FKStub())
        XCTAssertNil(vm.navigableForeignKeys(forTable: "orders")["a"])
        XCTAssertNil(vm.navigableForeignKeys(forTable: "orders")["b"])

        await vm.navigateForeignKey(fromColumn: "a", value: .int(1))
        XCTAssertEqual(vm.selectedTable?.name, "orders")
        XCTAssertTrue(vm.navigationStack.isEmpty)
    }

    func testCrossSchemaForeignKeyIsSuppressed() async {
        let vm = await browseOrders(FKStub())
        XCTAssertNil(vm.navigableForeignKeys(forTable: "orders")["z"])

        await vm.navigateForeignKey(fromColumn: "z", value: .int(1))
        XCTAssertEqual(vm.selectedTable?.name, "orders")
    }

    func testForeignKeyValueIsBoundNotInterpolated() async {
        let driver = FKStub()
        let vm = await browseOrders(driver)
        await vm.navigateForeignKey(fromColumn: "user_id", value: .text("o'brien; DROP"))

        let stmt = driver.runSelectCalls.last
        XCTAssertFalse(stmt?.sql.contains("DROP") ?? true)
        XCTAssertEqual(stmt?.binds, [.text("o'brien; DROP")])
    }

    func testNullForeignKeyValueDoesNotNavigate() async {
        let vm = await browseOrders(FKStub())
        await vm.navigateForeignKey(fromColumn: "user_id", value: .null)
        XCTAssertEqual(vm.selectedTable?.name, "orders")
        XCTAssertTrue(vm.navigationStack.isEmpty)
    }

    func testTableWithoutForeignKeysHasNoAffordance() async {
        let vm = await browseOrders(FKStub())
        XCTAssertTrue(vm.navigableForeignKeys(forTable: "customers").isEmpty)
    }
}
