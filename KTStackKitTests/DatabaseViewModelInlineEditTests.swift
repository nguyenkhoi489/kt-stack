import XCTest
@testable import KTStackKit

@MainActor
final class DatabaseViewModelInlineEditTests: XCTestCase {
    private final class InlineStub: RelationalDriver, @unchecked Sendable {
        let kind: DatabaseKind = .mysql
        var includePrimaryKey = true
        private(set) var updateCalls: [(values: [ColumnValue], key: [ColumnValue])] = []

        func ping() async throws {}
        func listDatabases() async throws -> [DatabaseInfo] {
            [DatabaseInfo(name: "db")]
        }

        func listTables(database _: String) async throws -> [TableInfo] {
            [TableInfo(name: "t")]
        }

        func columns(database _: String, table _: String) async throws -> [ColumnInfo] {
            var cols = [
                ColumnInfo(name: "name", dataType: "varchar", isNullable: true, isPrimaryKey: false),
                ColumnInfo(name: "qty", dataType: "int", isNullable: true, isPrimaryKey: false),
            ]
            if includePrimaryKey {
                cols.insert(
                    ColumnInfo(name: "id", dataType: "int", isNullable: false, isPrimaryKey: true),
                    at: 0
                )
            }
            return cols
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
            if includePrimaryKey {
                return QueryResult(
                    columns: [ColumnMeta(name: "id"), ColumnMeta(name: "name"), ColumnMeta(name: "qty")],
                    rows: [
                        [.int(1), .text("ann"), .int(10)],
                        [.int(2), .text("bob"), .int(20)],
                    ]
                )
            }
            return QueryResult(
                columns: [ColumnMeta(name: "name"), ColumnMeta(name: "qty")],
                rows: [[.text("ann"), .int(10)]]
            )
        }

        func openSession() async throws {}
        func closeSession() async {}
        func runSelect(_: DMLStatement, database _: String?) async throws -> QueryResult {
            QueryResult(columns: [], rows: [])
        }

        func insert(database _: String, table _: String, values _: [ColumnValue]) async throws {}
        func update(database _: String, table _: String, values: [ColumnValue], key: [ColumnValue]) async throws {
            updateCalls.append((values, key))
        }

        func delete(database _: String, table _: String, key _: [ColumnValue]) async throws {}
    }

    private func browse(
        _ driver: InlineStub,
        readOnly: Bool = false
    ) async -> DatabaseViewModel {
        let vm = DatabaseViewModel(makeDriver: { _, _ in driver }, passwordFor: { _ in nil })
        let profile = ConnectionProfile(
            name: "c",
            kind: .mysql,
            host: "127.0.0.1",
            port: 3306,
            user: "u",
            database: "db",
            readOnly: readOnly
        )
        await vm.select(profile: profile)
        await vm.select(database: "db")
        await vm.select(table: TableInfo(name: "t"))
        return vm
    }

    func testUpdateCellComposesSingleColumnUpdateKeyedByPrimaryKey() async {
        let driver = InlineStub()
        let vm = await browse(driver)
        await vm.updateCell(rowIndex: 0, column: "name", stringValue: "alice")

        XCTAssertEqual(driver.updateCalls.count, 1)
        XCTAssertEqual(driver.updateCalls.first?.values, [ColumnValue(column: "name", value: .text("alice"))])
        XCTAssertEqual(driver.updateCalls.first?.key, [ColumnValue(column: "id", value: .int(1))])
    }

    func testUpdateCellConvertsIntegerColumns() async {
        let driver = InlineStub()
        let vm = await browse(driver)
        await vm.updateCell(rowIndex: 0, column: "qty", stringValue: "99")
        XCTAssertEqual(driver.updateCalls.first?.values, [ColumnValue(column: "qty", value: .int(99))])
    }

    func testUpdateCellEmptyOnNullableBecomesNull() async {
        let driver = InlineStub()
        let vm = await browse(driver)
        await vm.updateCell(rowIndex: 0, column: "qty", stringValue: "")
        XCTAssertEqual(driver.updateCalls.first?.values, [ColumnValue(column: "qty", value: .null)])
    }

    func testUnchangedValueSkipsTheWrite() async {
        let driver = InlineStub()
        let vm = await browse(driver)
        await vm.updateCell(rowIndex: 0, column: "name", stringValue: "ann")
        XCTAssertTrue(driver.updateCalls.isEmpty)
    }

    func testReadOnlyConnectionBlocksInlineEdit() async {
        let driver = InlineStub()
        let vm = await browse(driver, readOnly: true)
        await vm.updateCell(rowIndex: 0, column: "name", stringValue: "alice")
        XCTAssertTrue(driver.updateCalls.isEmpty)
    }

    func testNoPrimaryKeyTableSurfacesEditError() async {
        let driver = InlineStub()
        driver.includePrimaryKey = false
        let vm = await browse(driver)
        await vm.updateCell(rowIndex: 0, column: "name", stringValue: "alice")
        XCTAssertTrue(driver.updateCalls.isEmpty)
        XCTAssertNotNil(vm.editError)
    }

    func testInlineCellConversionRules() {
        let intCol = ColumnInfo(name: "n", dataType: "int", isNullable: false, isPrimaryKey: false)
        let textCol = ColumnInfo(name: "s", dataType: "varchar", isNullable: true, isPrimaryKey: false)
        XCTAssertEqual(DatabaseViewModel.inlineCell(for: "42", column: intCol), .int(42))
        XCTAssertEqual(DatabaseViewModel.inlineCell(for: "x", column: intCol), .text("x"))
        XCTAssertEqual(DatabaseViewModel.inlineCell(for: "", column: textCol), .null)
        XCTAssertEqual(DatabaseViewModel.inlineCell(for: "hi", column: textCol), .text("hi"))
    }
}
