import XCTest
@testable import KDWarmKit


@MainActor
final class DatabaseViewModelTests: XCTestCase {

   
    private final class StubDriver: RelationalDriver, @unchecked Sendable {
        let kind: DatabaseKind = .mysql
        let tag: String
        var databasesDelay: Duration = .zero
        var queryShouldThrow: DatabaseError?
        var columnsResult: [ColumnInfo] = []
        var writeShouldThrow: DatabaseError?
        private(set) var paginateCalls: [(database: String, table: String, limit: Int, offset: Int)] = []
        private(set) var insertCalls: [[ColumnValue]] = []
        private(set) var updateCalls: [(values: [ColumnValue], key: [ColumnValue])] = []
        private(set) var deleteCalls: [[ColumnValue]] = []

        init(tag: String) { self.tag = tag }

        func ping() async throws {}

        func listDatabases() async throws -> [DatabaseInfo] {
            if databasesDelay > .zero { try? await Task.sleep(for: databasesDelay) }
            return [DatabaseInfo(name: "db_\(tag)")]
        }

        func listTables(database: String) async throws -> [TableInfo] {
            [TableInfo(name: "users"), TableInfo(name: "orders")]
        }

        func columns(database: String, table: String) async throws -> [ColumnInfo] { columnsResult }

        var indexesResult: [IndexInfo] = []
        func indexes(database: String, table: String) async throws -> [IndexInfo] { indexesResult }

        var foreignKeysResult: [ForeignKeyRelation] = []
        func foreignKeys(database: String) async throws -> [ForeignKeyRelation] { foreignKeysResult }

        func query(_ sql: String, database: String?) async throws -> QueryResult {
            if let queryShouldThrow { throw queryShouldThrow }
            return QueryResult(columns: [ColumnMeta(name: "n")], rows: [[.int(1)]])
        }

        func paginatedRows(database: String, table: String,
                           limit: Int, offset: Int) async throws -> QueryResult {
            paginateCalls.append((database, table, limit, offset))
            // Return a full page so the VM reports `hasMorePages`.
            let rows = (0..<limit).map { _ in [Cell.int(Int64(offset))] }
            return QueryResult(columns: [ColumnMeta(name: "id")], rows: rows)
        }

        func insert(database: String, table: String, values: [ColumnValue]) async throws {
            if let writeShouldThrow { throw writeShouldThrow }
            insertCalls.append(values)
        }

        func update(database: String, table: String,
                    values: [ColumnValue], key: [ColumnValue]) async throws {
            if let writeShouldThrow { throw writeShouldThrow }
            updateCalls.append((values, key))
        }

        func delete(database: String, table: String, key: [ColumnValue]) async throws {
            if let writeShouldThrow { throw writeShouldThrow }
            deleteCalls.append(key)
        }
    }

    private func makeVM(_ driver: StubDriver) -> DatabaseViewModel {
        DatabaseViewModel(makeDriver: { _, _ in driver }, passwordFor: { _ in nil })
    }

    func testSelectingConnectionLoadsDatabases() async {
        let vm = makeVM(StubDriver(tag: "a"))
        await vm.select(profile: .managedMySQL)
        XCTAssertEqual(vm.connection, .connected)
        XCTAssertEqual(vm.databases.map(\.name), ["db_a"])
        XCTAssertFalse(vm.isBusy)
    }

    func testSelectingTableLoadsFirstPage() async {
        let vm = makeVM(StubDriver(tag: "a"))
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db_a")
        XCTAssertEqual(vm.tables.map(\.name), ["users", "orders"])

        await vm.select(table: TableInfo(name: "users"))
        XCTAssertEqual(vm.pageOffset, 0)
        XCTAssertEqual(vm.result?.rowCount, vm.pageSize)
        XCTAssertTrue(vm.isTableBrowse)               // single-table browse → grid + pagination
        XCTAssertTrue(vm.hasMorePages)
    }

    func testRunningSQLPopulatesResult() async {
        let vm = makeVM(StubDriver(tag: "a"))
        await vm.select(profile: .managedMySQL)
        await vm.runSQL("SELECT 1")
        XCTAssertEqual(vm.result?.columns.map(\.name), ["n"])
        XCTAssertNil(vm.resultError)
        XCTAssertFalse(vm.isTableBrowse)              // arbitrary query → read-only
    }

    func testRunningInvalidSQLSurfacesError() async {
        let driver = StubDriver(tag: "a")
        driver.queryShouldThrow = .syntax("bad SQL")
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        await vm.runSQL("SELEKT 1")
        XCTAssertNil(vm.result)
        XCTAssertEqual(vm.resultError, DatabaseError.syntax("bad SQL").message)
    }

    func testPaginationAdvancesOffset() async {
        let driver = StubDriver(tag: "a")
        let vm = makeVM(driver)
        vm.pageSize = 10
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db_a")
        await vm.select(table: TableInfo(name: "users"))
        await vm.nextPage()
        XCTAssertEqual(vm.pageOffset, 10)
        await vm.previousPage()
        XCTAssertEqual(vm.pageOffset, 0)
        // first page, next page, prev page → three paginated reads at offsets 0, 10, 0.
        XCTAssertEqual(driver.paginateCalls.map(\.offset), [0, 10, 0])
    }

    func testSelectingDatabaseBuildsSchemaCatalog() async {
        let driver = StubDriver(tag: "a")
        driver.columnsResult = [
            ColumnInfo(name: "id", dataType: "int", isNullable: false, isPrimaryKey: true),
            ColumnInfo(name: "name", dataType: "text", isNullable: true, isPrimaryKey: false),
        ]
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db_a")

        XCTAssertEqual(vm.schemaCatalog.tables, ["users", "orders"])
        XCTAssertEqual(vm.schemaCatalog.columns(of: "users"), ["id", "name"])
        XCTAssertEqual(vm.schemaCatalog.columns(of: "orders"), ["id", "name"])
    }

    func testReselectingConnectionResetsSchemaCatalog() async {
        let driver = StubDriver(tag: "a")
        driver.columnsResult = [ColumnInfo(name: "id", dataType: "int",
                                           isNullable: false, isPrimaryKey: true)]
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db_a")
        XCTAssertFalse(vm.schemaCatalog.tables.isEmpty)

        await vm.select(profile: .managedMySQL)
        XCTAssertTrue(vm.schemaCatalog.tables.isEmpty)
    }

    func testUnsupportedEngineFailsCleanly() async {
        // Factory returns nil for a non-MySQL kind → an explicit connection failure, not a crash.
        let vm = DatabaseViewModel(makeDriver: { _, _ in nil }, passwordFor: { _ in nil })
        let pg = ConnectionProfile(name: "pg", kind: .postgres, host: "h", port: 5432,
                                   user: "u", database: "d")
        await vm.select(profile: pg)
        if case .failed = vm.connection {} else { XCTFail("expected failed connection") }
        XCTAssertFalse(vm.isBusy)
    }

    // MARK: - Row CRUD

    private let pkColumn = ColumnInfo(name: "id", dataType: "int",
                                      isNullable: false, isPrimaryKey: true)

    /// Connect, open a database, and browse a table whose columns are `cols`.
    private func browseTable(_ driver: StubDriver, columns cols: [ColumnInfo]) async -> DatabaseViewModel {
        driver.columnsResult = cols
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db_a")
        await vm.select(table: TableInfo(name: "users"))
        return vm
    }

    func testCanEditRowsRequiresTableBrowseAndPrimaryKey() async {
        let withPK = await browseTable(StubDriver(tag: "a"), columns: [pkColumn])
        XCTAssertTrue(withPK.canEditRows)
        XCTAssertNil(withPK.editDisabledReason)

        let noPK = await browseTable(StubDriver(tag: "b"),
            columns: [ColumnInfo(name: "x", dataType: "int", isNullable: true, isPrimaryKey: false)])
        XCTAssertFalse(noPK.canEditRows)
        XCTAssertNotNil(noPK.editDisabledReason)
    }

    func testSQLResultIsNeverEditable() async {
        let vm = makeVM(StubDriver(tag: "a"))
        await vm.select(profile: .managedMySQL)
        await vm.runSQL("SELECT 1")
        XCTAssertFalse(vm.canEditRows)
        XCTAssertEqual(vm.editDisabledReason, "Editing is only available when browsing a single table.")
    }

    func testInsertRowCallsDriverAndReloads() async {
        let driver = StubDriver(tag: "a")
        let vm = await browseTable(driver, columns: [pkColumn])
        let before = driver.paginateCalls.count
        await vm.insertRow([ColumnValue(column: "id", value: .int(9))])
        XCTAssertEqual(driver.insertCalls.count, 1)
        XCTAssertEqual(driver.paginateCalls.count, before + 1)   // page reloaded after the write
    }

    func testUpdateRowBuildsKeyFromPrimaryKey() async {
        let driver = StubDriver(tag: "a")
        let vm = await browseTable(driver, columns: [pkColumn])
        // First page row 0 is [.int(0)] for column "id" (the PK) per the stub.
        await vm.updateRow(at: 0, values: [ColumnValue(column: "name", value: .text("z"))])
        XCTAssertEqual(driver.updateCalls.count, 1)
        XCTAssertEqual(driver.updateCalls.first?.key, [ColumnValue(column: "id", value: .int(0))])
        XCTAssertEqual(driver.updateCalls.first?.values, [ColumnValue(column: "name", value: .text("z"))])
    }

    func testDeleteRowBuildsKeyFromPrimaryKey() async {
        let driver = StubDriver(tag: "a")
        let vm = await browseTable(driver, columns: [pkColumn])
        await vm.deleteRow(at: 0)
        XCTAssertEqual(driver.deleteCalls, [[ColumnValue(column: "id", value: .int(0))]])
    }

    func testWriteFailureSurfacesEditError() async {
        let driver = StubDriver(tag: "a")
        driver.writeShouldThrow = .connection("affected 3 rows; aborted")
        let vm = await browseTable(driver, columns: [pkColumn])
        await vm.deleteRow(at: 0)
        XCTAssertEqual(vm.editError, DatabaseError.connection("affected 3 rows; aborted").message)
    }

    func testDestructiveSQLHeldForConfirmThenRuns() async {
        let driver = StubDriver(tag: "a")
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        await vm.runSQL("DELETE FROM t")             // keyless → held, not run
        XCTAssertEqual(vm.pendingDangerousSQL, "DELETE FROM t")
        XCTAssertNil(vm.result)

        await vm.runSQL("DELETE FROM t", confirmed: true)
        XCTAssertNil(vm.pendingDangerousSQL)         // cleared once confirmed
        XCTAssertNotNil(vm.result)
    }

    // MARK: - Read-only gates write/DDL/import paths

    func testReadOnlyConnectionRefusesDDL() async {
        let driver = StubDriver(tag: "a")
        let vm = makeVM(driver)
        let ro = ConnectionProfile(name: "ro", kind: .mysql, host: "db.example.com", port: 3306,
                                   user: "u", database: "d", readOnly: true)
        await vm.select(profile: ro)
        await vm.select(database: "db_a")
        await vm.select(table: TableInfo(name: "users"))
        vm.prepareDropTable()
        XCTAssertNotNil(vm.pendingDDL)        // staging is allowed (composition is pure)
        await vm.confirmDDL()
        XCTAssertEqual(vm.ddlError, "This connection is read-only.")   // running is refused
    }

    func testReadOnlyConnectionRefusesImport() async {
        let driver = StubDriver(tag: "a")
        let vm = makeVM(driver)
        let ro = ConnectionProfile(name: "ro", kind: .mysql, host: "db.example.com", port: 3306,
                                   user: "u", database: "d", readOnly: true)
        await vm.select(profile: ro)
        let dummy = FileManager.default.temporaryDirectory.appendingPathComponent("x.sql")
        await vm.importDatabase(into: "target", from: dummy)
        if case .failed(let message) = vm.dumpStatus {
            XCTAssertTrue(message.contains("read-only"))
        } else {
            XCTFail("expected a read-only failure status")
        }
    }

    func testReadOnlyConnectionRefusesCreateDatabase() async {
        let driver = StubDriver(tag: "a")
        let vm = makeVM(driver)
        let ro = ConnectionProfile(name: "ro", kind: .mysql, host: "db.example.com", port: 3306,
                                   user: "u", database: "d", readOnly: true)
        await vm.select(profile: ro)
        let created = await vm.createDatabase(named: "target")
        XCTAssertFalse(created)
        if case .failed(let message) = vm.dumpStatus {
            XCTAssertTrue(message.contains("read-only"))
        } else {
            XCTFail("expected a read-only failure status")
        }
    }

    func testStaleConnectResultIsDiscarded() async {
        // A slow connection started first must not clobber a faster one that supersedes it.
        let slow = StubDriver(tag: "slow"); slow.databasesDelay = .milliseconds(120)
        let fast = StubDriver(tag: "fast")
        var next: StubDriver = slow
        let vm = DatabaseViewModel(makeDriver: { _, _ in next }, passwordFor: { _ in nil })

        async let first: Void = vm.select(profile: .managedMySQL)
        // Let the slow select reach its awaiting listDatabases, then supersede it.
        try? await Task.sleep(for: .milliseconds(20))
        next = fast
        await vm.select(profile: .managedMySQL)
        await first

        XCTAssertEqual(vm.databases.map(\.name), ["db_fast"])   // fast won; slow discarded
        XCTAssertEqual(vm.connection, .connected)
    }
}
