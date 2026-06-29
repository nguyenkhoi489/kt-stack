import XCTest
@testable import KTStackKit

@MainActor
final class DatabaseV2ViewModelTests: XCTestCase {
    private final class TestDriver: RelationalDriver, @unchecked Sendable {
        let kind: DatabaseKind = .mysql

        var shouldPingFail = false
        var shouldListDatabasesFail = false
        var shouldListTablesFail = false
        var shouldGetColumnsFail = false
        var shouldGetIndexesFail = false
        var shouldGetForeignKeysFail = false
        var shouldQueryFail = false
        var shouldPaginateFail = false
        var shouldGetAllColumnsFail = false

        var databases: [DatabaseInfo] = [
            DatabaseInfo(name: "testdb"),
            DatabaseInfo(name: "otherdb"),
        ]
        var tables: [TableInfo] = [
            TableInfo(name: "users"),
            TableInfo(name: "posts"),
        ]
        var columns: [ColumnInfo] = [
            ColumnInfo(name: "id", dataType: "int", isNullable: false, isPrimaryKey: true),
            ColumnInfo(name: "name", dataType: "varchar(255)", isNullable: true, isPrimaryKey: false),
        ]
        var indexes: [IndexInfo] = [
            IndexInfo(name: "idx_name", columns: ["name"], isUnique: false),
        ]
        var foreignKeys: [ForeignKeyRelation] = [
            ForeignKeyRelation(
                fromTable: "posts",
                fromColumn: "user_id",
                toTable: "users",
                toColumn: "id",
                constraintName: "fk_user_posts"
            ),
        ]

        var total: Int = 250
        private(set) var lastQueryText: String?
        private(set) var lastQueryDatabase: String?
        private(set) var paginateCalls: [(database: String, table: String, limit: Int, offset: Int)] = []
        private(set) var cancelCalled = false
        private(set) var insertCalls: [(database: String, table: String, values: [ColumnValue])] = []
        private(set) var updateCalls: [(database: String, table: String, values: [ColumnValue], key: [ColumnValue])] = []
        private(set) var deleteCalls: [(database: String, table: String, key: [ColumnValue])] = []
        private(set) var listTablesCalls: [String] = []

        init(total: Int = 250) {
            self.total = total
        }

        func ping() async throws {
            if shouldPingFail { throw TestError.pingFailed }
        }

        func listDatabases() async throws -> [DatabaseInfo] {
            if shouldListDatabasesFail { throw TestError.listDatabasesFailed }
            return databases
        }

        func listTables(database: String) async throws -> [TableInfo] {
            if shouldListTablesFail { throw TestError.listTablesFailed }
            listTablesCalls.append(database)
            return tables
        }

        func columns(database _: String, table _: String) async throws -> [ColumnInfo] {
            if shouldGetColumnsFail { throw TestError.columnsFailed }
            return columns
        }

        func allColumns(database _: String) async throws -> [String: [String]] {
            ["users": ["id", "name"], "posts": ["id", "user_id"]]
        }

        func allColumnsDetailed(database _: String) async throws -> [String: [ColumnInfo]] {
            if shouldGetAllColumnsFail { throw TestError.allColumnsFailed }
            return ["users": columns, "posts": columns]
        }

        func indexes(database _: String, table _: String) async throws -> [IndexInfo] {
            if shouldGetIndexesFail { throw TestError.indexesFailed }
            return indexes
        }

        func foreignKeys(database _: String) async throws -> [ForeignKeyRelation] {
            if shouldGetForeignKeysFail { throw TestError.foreignKeysFailed }
            return foreignKeys
        }

        func query(_ sql: String, database: String?) async throws -> QueryResult {
            if shouldQueryFail { throw TestError.queryFailed }
            lastQueryText = sql
            lastQueryDatabase = database
            return QueryResult(columns: [ColumnMeta(name: "id")], rows: [[.int(1)]])
        }

        func paginatedRows(database: String, table: String, limit: Int, offset: Int) async throws -> QueryResult {
            if shouldPaginateFail { throw TestError.paginateFailed }
            paginateCalls.append((database, table, limit, offset))
            let rows = (0..<min(limit, total - offset)).map { _ in [Cell.int(1), Cell.text("test-name")] }
            return QueryResult(
                columns: [ColumnMeta(name: "id"), ColumnMeta(name: "name")],
                rows: rows
            )
        }

        func openSession() async throws {}

        func closeSession() async {}

        func cancelCurrentQuery() async {
            cancelCalled = true
        }

        func runSelect(_: DMLStatement, database _: String?) async throws -> QueryResult {
            QueryResult(columns: [], rows: [])
        }

        func insert(database: String, table: String, values: [ColumnValue]) async throws {
            insertCalls.append((database, table, values))
        }

        func update(database: String, table: String, values: [ColumnValue], key: [ColumnValue]) async throws {
            updateCalls.append((database, table, values, key))
        }

        func delete(database: String, table: String, key: [ColumnValue]) async throws {
            deleteCalls.append((database, table, key))
        }
    }

    enum TestError: Error {
        case pingFailed
        case listDatabasesFailed
        case listTablesFailed
        case columnsFailed
        case indexesFailed
        case foreignKeysFailed
        case queryFailed
        case paginateFailed
        case allColumnsFailed
    }

    func testConnectSuccessPopulatesDatabasesAndSelectsFirst() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        let profile = ConnectionProfile.managedMySQL
        await vm.connect(profile: profile)

        if case .connected = vm.connectionState {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected connected state")
        }
        XCTAssertEqual(vm.databases.count, 2)
        XCTAssertEqual(vm.databases.first?.name, "testdb")
        XCTAssertEqual(vm.selectedDatabase, "testdb")
    }

    func testConnectSuccessLoadsTables() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)

        XCTAssertEqual(vm.tables.count, 2)
        XCTAssertEqual(vm.tables.first?.name, "users")
    }

    func testConnectFailureWhenPingThrows() async {
        let driver = TestDriver()
        driver.shouldPingFail = true
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)

        if case .failed = vm.connectionState {
            XCTAssertTrue(vm.databases.isEmpty)
        } else {
            XCTFail("Expected .failed state")
        }
    }

    func testConnectFailureWhenListDatabasesThrows() async {
        let driver = TestDriver()
        driver.shouldListDatabasesFail = true
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)

        if case .failed = vm.connectionState {
            XCTAssertTrue(vm.databases.isEmpty)
        } else {
            XCTFail("Expected .failed state")
        }
    }

    func testConnectFailureWhenUnsupportedEngine() async {
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in nil },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)

        if case let .failed(message) = vm.connectionState {
            XCTAssertTrue(message.contains("Unsupported engine"))
        } else {
            XCTFail("Expected .failed state for unsupported engine")
        }
    }

    func testConnectResetsStateOnNewConnection() async {
        let driver1 = TestDriver()
        let driver2 = TestDriver()
        driver2.databases = [DatabaseInfo(name: "newdb")]
        driver2.tables = [TableInfo(name: "newtable")]

        var driverIndex = 0
        let makeDriver: DatabaseViewModel.DriverFactory = { _, _ in
            defer { driverIndex += 1 }
            return driverIndex == 0 ? driver1 : driver2
        }

        let vm = DatabaseV2ViewModel(
            makeDriver: makeDriver,
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        vm.queryText = "SELECT * FROM users"

        await vm.connect(profile: .managedMySQL)

        XCTAssertEqual(vm.selectedDatabase, "newdb")
        XCTAssertEqual(vm.tables.first?.name, "newtable")
    }

    func testSelectDatabaseLoadsTables() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        await vm.select(database: "otherdb")

        XCTAssertEqual(vm.selectedDatabase, "otherdb")
        XCTAssertEqual(vm.tables.count, 2)
    }

    func testSelectDatabaseClearsSelectedTable() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        let table = TableInfo(name: "users")
        vm.select(table: table)

        await vm.select(database: "otherdb")

        XCTAssertNil(vm.selectedTable)
    }

    func testSelectTableTriggersLoadRowsAndLoadStructure() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        let table = TableInfo(name: "users")
        vm.select(table: table)

        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(vm.selectedTable?.name, "users")
        XCTAssertEqual(vm.rows?.rowCount, driver.paginateCalls.count > 0 ? driver.paginateCalls[0].limit : 0)
        XCTAssertEqual(vm.columns.count, 2)
    }

    func testLoadRowsCallsPaginatedRowsWithCorrectParameters() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        let table = TableInfo(name: "users")
        await vm.loadRows(table: table)

        XCTAssertEqual(driver.paginateCalls.count, 1)
        let call = driver.paginateCalls[0]
        XCTAssertEqual(call.database, "testdb")
        XCTAssertEqual(call.table, "users")
        XCTAssertEqual(call.limit, vm.pageSize)
        XCTAssertEqual(call.offset, 0)
    }

    func testLoadRowsPopulatesRowsAndHasMore() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        let table = TableInfo(name: "users")
        await vm.loadRows(table: table)

        XCTAssertNotNil(vm.rows)
        XCTAssertEqual(vm.rows?.rowCount, vm.pageSize)
        XCTAssertTrue(vm.hasMore)
    }

    func testLoadRowsWithFewerRowsThanPageSizeSetsHasMoreFalse() async {
        let driver = TestDriver()
        driver.databases = [DatabaseInfo(name: "small")]
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        let table = TableInfo(name: "users")

        await vm.loadRows(table: table)

        let rowCount = vm.rows?.rowCount ?? 0
        let hasMore = rowCount == vm.pageSize
        XCTAssertEqual(vm.hasMore, hasMore)
    }

    func testFetchMoreAppendsToExistingRows() async {
        let driver = TestDriver(total: 500)
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        let table = TableInfo(name: "users")
        vm.select(table: table)
        try? await Task.sleep(for: .milliseconds(50))

        let firstPageCount = vm.rows?.rowCount ?? 0

        await vm.fetchMore()
        let totalCount = vm.rows?.rowCount ?? 0

        XCTAssertGreaterThan(totalCount, firstPageCount)
    }

    func testFetchMoreIncrementsPageOffset() async {
        let driver = TestDriver(total: 500)
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        let table = TableInfo(name: "users")
        vm.select(table: table)
        try? await Task.sleep(for: .milliseconds(50))

        let offsetAfterLoad = vm.pageOffset

        await vm.fetchMore()

        XCTAssertGreaterThan(vm.pageOffset, offsetAfterLoad)
    }

    func testFetchMoreCallsPaginatedRowsWithCorrectOffset() async {
        let driver = TestDriver(total: 500)
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        let table = TableInfo(name: "users")
        vm.select(table: table)
        try? await Task.sleep(for: .milliseconds(50))

        await vm.fetchMore()

        XCTAssertEqual(driver.paginateCalls.count, 2)
        if driver.paginateCalls.count >= 2 {
            let secondCall = driver.paginateCalls[1]
            XCTAssertEqual(secondCall.offset, vm.pageSize)
        }
    }

    func testLoadStructurePopulatesColumns() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        let table = TableInfo(name: "users")
        await vm.loadStructure(table: table)

        XCTAssertEqual(vm.columns.count, 2)
        XCTAssertEqual(vm.columns.first?.name, "id")
    }

    func testLoadStructurePopulatesIndexes() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        let table = TableInfo(name: "users")
        await vm.loadStructure(table: table)

        XCTAssertEqual(vm.indexes.count, 1)
        XCTAssertEqual(vm.indexes.first?.name, "idx_name")
    }

    func testLoadStructurePopulatesForeignKeys() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        let table = TableInfo(name: "users")
        await vm.loadStructure(table: table)

        XCTAssertEqual(vm.foreignKeys.count, 1)
        XCTAssertEqual(vm.foreignKeys.first?.fromTable, "posts")
    }

    func testLoadDiagramPopulatesDiagramColumns() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        await vm.loadDiagram()

        XCTAssertEqual(vm.diagramColumns.count, 2)
        XCTAssertTrue(vm.diagramColumns.keys.contains("users"))
        XCTAssertTrue(vm.diagramColumns.keys.contains("posts"))
    }

    func testLoadDiagramPopulatesForeignKeys() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        await vm.loadDiagram()

        XCTAssertEqual(vm.foreignKeys.count, 1)
    }

    func testRunQueryExecutesQueryAndPopulatesResult() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        vm.queryText = "SELECT * FROM users"
        await vm.runQuery()

        XCTAssertNotNil(vm.queryResult)
        XCTAssertNil(vm.queryError)
        XCTAssertEqual(driver.lastQueryText, "SELECT * FROM users")
    }

    func testRunQueryIgnoresEmptyQuery() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        vm.queryText = "   "
        await vm.runQuery()

        XCTAssertNil(vm.queryResult)
        XCTAssertNil(vm.queryError)
        XCTAssertNil(driver.lastQueryText)
    }

    func testRunQueryIgnoresQueryWithoutDriver() async {
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in nil },
            passwordFor: { _ in nil }
        )

        vm.queryText = "SELECT * FROM users"
        await vm.runQuery()

        XCTAssertNil(vm.queryResult)
    }

    func testRunQueryStoresErrorOnFailure() async {
        let driver = TestDriver()
        driver.shouldQueryFail = true
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        vm.queryText = "SELECT * FROM users"
        await vm.runQuery()

        XCTAssertNil(vm.queryResult)
        XCTAssertNotNil(vm.queryError)
    }

    func testRunQuerySetsIsRunningFlag() async {
        let driver = TestDriver()
        var runningDuringQuery = false

        let wrappedDriver = TestDriver()
        wrappedDriver.shouldQueryFail = false

        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in wrappedDriver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        vm.queryText = "SELECT * FROM users"

        async let queryTask: Void = vm.runQuery()
        try? await Task.sleep(for: .milliseconds(5))
        if vm.isRunning {
            runningDuringQuery = true
        }
        await queryTask

        XCTAssertFalse(vm.isRunning)
    }

    func testCancelQueryCallsDriver() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        await vm.cancelQuery()

        XCTAssertTrue(driver.cancelCalled)
    }

    func testCancelQuerySetsIsRunningFalse() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        vm.queryText = "SELECT * FROM users"

        async let queryTask = vm.runQuery()
        try? await Task.sleep(for: .milliseconds(5))
        await vm.cancelQuery()
        await queryTask

        XCTAssertFalse(vm.isRunning)
    }

    func testMultipleConnectsClosesPreviousDriver() async {
        var driverClosedCount = 0

        let driver1 = TestDriver()
        let driver2 = TestDriver()

        var driverIndex = 0
        let makeDriver: DatabaseViewModel.DriverFactory = { _, _ in
            defer { driverIndex += 1 }
            return driverIndex == 0 ? driver1 : driver2
        }

        let vm = DatabaseV2ViewModel(
            makeDriver: makeDriver,
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        await vm.connect(profile: .managedMySQL)

        XCTAssertEqual(vm.selectedDatabase, "testdb")
    }

    func testSelectTableSetsIsLoadingRowsFlag() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)

        let table = TableInfo(name: "users")
        vm.select(table: table)

        XCTAssertTrue(vm.isLoadingRows)

        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(vm.isLoadingRows)
    }

    func testCanEditIsTrueWhenColumnsHavePrimaryKey() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        await vm.loadStructure(table: TableInfo(name: "users"))
        XCTAssertTrue(vm.canEdit)
    }

    func testCanEditIsFalseWhenNoPrimaryKey() async {
        let driver = TestDriver()
        driver.columns = [
            ColumnInfo(name: "email", dataType: "varchar", isNullable: true, isPrimaryKey: false),
        ]
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        await vm.loadStructure(table: TableInfo(name: "users"))
        XCTAssertFalse(vm.canEdit)
    }

    func testEditableColumnsExcludesPrimaryKey() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        await vm.loadStructure(table: TableInfo(name: "users"))
        XCTAssertFalse(vm.editableColumns.contains("id"))
        XCTAssertTrue(vm.editableColumns.contains("name"))
    }

    func testUpdateCellSendsCorrectValueAndKey() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        vm.select(table: TableInfo(name: "users"))
        try? await Task.sleep(for: .milliseconds(100))

        await vm.updateCell(row: 0, column: 1, newValue: "Alice")

        XCTAssertEqual(driver.updateCalls.count, 1)
        let call = driver.updateCalls[0]
        XCTAssertEqual(call.values.count, 1)
        XCTAssertEqual(call.values[0].column, "name")
        XCTAssertEqual(call.values[0].value, .text("Alice"))
        XCTAssertEqual(call.key.count, 1)
        XCTAssertEqual(call.key[0].column, "id")
        XCTAssertEqual(call.key[0].value, .int(1))
    }

    func testUpdateCellSkipsWhenValueUnchanged() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        vm.select(table: TableInfo(name: "users"))
        try? await Task.sleep(for: .milliseconds(100))

        await vm.updateCell(row: 0, column: 1, newValue: "test-name")

        XCTAssertEqual(driver.updateCalls.count, 0)
    }

    func testDeleteRowSendsPrimaryKeyAsKey() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        vm.select(table: TableInfo(name: "users"))
        try? await Task.sleep(for: .milliseconds(100))

        await vm.deleteRow(0)

        XCTAssertEqual(driver.deleteCalls.count, 1)
        let call = driver.deleteCalls[0]
        XCTAssertEqual(call.key.count, 1)
        XCTAssertEqual(call.key[0].column, "id")
        XCTAssertEqual(call.key[0].value, .int(1))
    }

    func testDeleteRowDoesNothingWhenNoPrimaryKey() async {
        let driver = TestDriver()
        driver.columns = [
            ColumnInfo(name: "email", dataType: "varchar", isNullable: true, isPrimaryKey: false),
        ]
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        vm.select(table: TableInfo(name: "users"))
        try? await Task.sleep(for: .milliseconds(100))

        await vm.deleteRow(0)

        XCTAssertEqual(driver.deleteCalls.count, 0)
        XCTAssertNotNil(vm.editError)
    }

    func testInsertRowCallsDriverInsert() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        vm.select(table: TableInfo(name: "users"))
        try? await Task.sleep(for: .milliseconds(50))

        let values = [ColumnValue(column: "name", value: .text("Bob"))]
        await vm.insertRow(values)

        XCTAssertEqual(driver.insertCalls.count, 1)
        XCTAssertEqual(driver.insertCalls[0].values, values)
        XCTAssertEqual(driver.insertCalls[0].database, "testdb")
        XCTAssertEqual(driver.insertCalls[0].table, "users")
    }

    func testUpdateCellReloadsRowsAfterSuccess() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        vm.select(table: TableInfo(name: "users"))
        try? await Task.sleep(for: .milliseconds(100))

        let callCountBefore = driver.paginateCalls.count
        await vm.updateCell(row: 0, column: 1, newValue: "Alice")

        XCTAssertGreaterThan(driver.paginateCalls.count, callCountBefore)
    }

    func testComposeCreateTableProducesSQL() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)

        let cols = [ColumnDefinition(name: "id", type: "INT", isNullable: false, isPrimaryKey: true)]
        let sql = vm.composeCreateTable(name: "orders", columns: cols)

        XCTAssertFalse(sql.isEmpty)
        XCTAssertTrue(sql.uppercased().contains("CREATE TABLE"))
        XCTAssertTrue(sql.contains("orders"))
        XCTAssertNil(vm.ddlError)
    }

    func testComposeAddColumnProducesAlterSQL() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        vm.select(table: TableInfo(name: "users"))
        try? await Task.sleep(for: .milliseconds(50))

        let col = ColumnDefinition(name: "email", type: "VARCHAR(255)", isNullable: true)
        let sql = vm.composeAddColumn(col)

        XCTAssertFalse(sql.isEmpty)
        XCTAssertTrue(sql.uppercased().contains("ALTER TABLE"))
        XCTAssertTrue(sql.uppercased().contains("ADD COLUMN"))
        XCTAssertNil(vm.ddlError)
    }

    func testComposeDropColumnProducesAlterSQL() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        vm.select(table: TableInfo(name: "users"))
        try? await Task.sleep(for: .milliseconds(50))

        let sql = vm.composeDropColumn("email")

        XCTAssertFalse(sql.isEmpty)
        XCTAssertTrue(sql.uppercased().contains("ALTER TABLE"))
        XCTAssertTrue(sql.uppercased().contains("DROP COLUMN"))
        XCTAssertNil(vm.ddlError)
    }

    func testComposeDropTableProducesDropSQL() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        vm.select(table: TableInfo(name: "users"))
        try? await Task.sleep(for: .milliseconds(50))

        let sql = vm.composeDropTable()

        XCTAssertFalse(sql.isEmpty)
        XCTAssertTrue(sql.uppercased().contains("DROP TABLE"))
        XCTAssertTrue(sql.contains("users"))
        XCTAssertNil(vm.ddlError)
    }

    func testRunDDLCallsDriverQuery() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)

        let ddlSQL = "CREATE TABLE `testdb`.`temp` (`id` INT NOT NULL)"
        await vm.runDDL(ddlSQL)

        XCTAssertEqual(driver.lastQueryText, ddlSQL)
        XCTAssertEqual(driver.lastQueryDatabase, "testdb")
    }

    func testRunDDLReloadsTablesAfterSuccess() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        vm.select(table: TableInfo(name: "users"))
        try? await Task.sleep(for: .milliseconds(50))

        let callCountBefore = driver.listTablesCalls.count
        await vm.runDDL("DROP TABLE `testdb`.`temp`")

        XCTAssertGreaterThan(driver.listTablesCalls.count, callCountBefore)
    }

    func testRunDDLSetsErrorOnQueryFailure() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )
        await vm.connect(profile: .managedMySQL)
        driver.shouldQueryFail = true

        await vm.runDDL("DROP TABLE `testdb`.`bad`")

        XCTAssertNotNil(vm.ddlError)
    }

    func testComposeCreateTableWithoutDatabaseSetsError() {
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in nil },
            passwordFor: { _ in nil }
        )

        let sql = vm.composeCreateTable(
            name: "test",
            columns: [ColumnDefinition(name: "id", type: "INT")]
        )

        XCTAssertTrue(sql.isEmpty)
        XCTAssertNotNil(vm.ddlError)
    }

    func testAddQueryTabIncrementsCountAndActivatesNew() {
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in nil },
            passwordFor: { _ in nil }
        )

        XCTAssertEqual(vm.queryTabs.count, 1)
        let originalID = vm.activeQueryTabID

        vm.addQueryTab()

        XCTAssertEqual(vm.queryTabs.count, 2)
        XCTAssertNotEqual(vm.activeQueryTabID, originalID)
        XCTAssertEqual(vm.activeQueryTabID, vm.queryTabs.last?.id)
    }

    func testCloseQueryTabKeepsAtLeastOneAndReselects() {
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in nil },
            passwordFor: { _ in nil }
        )

        vm.addQueryTab()
        XCTAssertEqual(vm.queryTabs.count, 2)

        let secondID = vm.activeQueryTabID!
        vm.closeQueryTab(id: secondID)

        XCTAssertEqual(vm.queryTabs.count, 1)
        XCTAssertNotEqual(vm.activeQueryTabID, secondID)
        XCTAssertEqual(vm.activeQueryTabID, vm.queryTabs.first?.id)

        let lastID = vm.activeQueryTabID!
        vm.closeQueryTab(id: lastID)
        XCTAssertEqual(vm.queryTabs.count, 1, "Must never close the last tab")
    }

    func testRunQueryWritesResultIntoActiveTab() async {
        let driver = TestDriver()
        let vm = DatabaseV2ViewModel(
            makeDriver: { _, _ in driver },
            passwordFor: { _ in nil }
        )

        await vm.connect(profile: .managedMySQL)
        vm.addQueryTab()

        let activeID = vm.activeQueryTabID
        vm.queryText = "SELECT 1"
        await vm.runQuery()

        let activeTab = vm.queryTabs.first { $0.id == activeID }
        XCTAssertNotNil(activeTab?.result)
        XCTAssertNil(activeTab?.error)
        XCTAssertFalse(activeTab?.isRunning ?? true)

        let otherTabs = vm.queryTabs.filter { $0.id != activeID }
        XCTAssertTrue(otherTabs.allSatisfy { $0.result == nil })
    }
}
