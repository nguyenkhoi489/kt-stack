import XCTest
@testable import KTStackKit

@MainActor
final class DatabaseViewModelLazyCatalogTests: XCTestCase {

    private final class CatalogStub: RelationalDriver, @unchecked Sendable {
        let kind: DatabaseKind = .mysql
        var databasesDelay: Duration = .zero
        private(set) var allColumnsCalls = 0
        private(set) var foreignKeysCalls = 0
        var allColumnsFailNextCall = false

        func ping() async throws {}
        func listDatabases() async throws -> [DatabaseInfo] {
            if databasesDelay > .zero { try? await Task.sleep(for: databasesDelay) }
            return [DatabaseInfo(name: "db")]
        }
        func listTables(database: String) async throws -> [TableInfo] {
            [TableInfo(name: "users"), TableInfo(name: "orders")]
        }
        func columns(database: String, table: String) async throws -> [ColumnInfo] {
            [ColumnInfo(name: "id", dataType: "int", isNullable: false, isPrimaryKey: true)]
        }
        func allColumns(database: String) async throws -> [String: [String]] {
            allColumnsCalls += 1
            if allColumnsFailNextCall {
                allColumnsFailNextCall = false
                throw DatabaseError.connection("introspection failed")
            }
            return ["users": ["id", "name"], "orders": ["id", "total"]]
        }
        func indexes(database: String, table: String) async throws -> [IndexInfo] { [] }
        func foreignKeys(database: String) async throws -> [ForeignKeyRelation] {
            foreignKeysCalls += 1
            return [ForeignKeyRelation(fromTable: "orders", fromColumn: "user_id",
                                       toTable: "users", toColumn: "id")]
        }
        func query(_ sql: String, database: String?) async throws -> QueryResult {
            QueryResult(columns: [], rows: [])
        }
        func paginatedRows(database: String, table: String,
                           limit: Int, offset: Int) async throws -> QueryResult {
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

    private func makeVM(_ driver: CatalogStub) -> DatabaseViewModel {
        DatabaseViewModel(makeDriver: { _, _ in driver }, passwordFor: { _ in nil })
    }

    func testSelectingDatabaseDoesNotEagerlyIntrospectColumns() async {
        let driver = CatalogStub()
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db")

        XCTAssertEqual(driver.allColumnsCalls, 0)
        XCTAssertEqual(vm.schemaCatalog.tables, ["users", "orders"])
        XCTAssertTrue(vm.schemaCatalog.columns(of: "users").isEmpty)
    }

    func testEnsureSchemaCatalogLoadsColumnsExactlyOnce() async {
        let driver = CatalogStub()
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db")

        await vm.ensureSchemaCatalogLoaded()
        XCTAssertEqual(driver.allColumnsCalls, 1)
        XCTAssertEqual(vm.schemaCatalog.columns(of: "users"), ["id", "name"])
        XCTAssertEqual(vm.schemaCatalog.columns(of: "orders"), ["id", "total"])

        await vm.ensureSchemaCatalogLoaded()
        XCTAssertEqual(driver.allColumnsCalls, 1)
    }

    func testEnsureCatalogAndRelationsComposeWithoutClobbering() async {
        let driver = CatalogStub()
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db")

        await vm.loadRelationsIfNeeded()
        await vm.ensureSchemaCatalogLoaded()

        XCTAssertEqual(vm.schemaCatalog.columns(of: "users"), ["id", "name"])
        XCTAssertEqual(vm.schemaCatalog.relations.count, 1)
    }

    func testEnsureSchemaCatalogPreservesDetailedColumns() async {
        let driver = CatalogStub()
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db")

        await vm.ensureDetailedColumnsLoaded()
        XCTAssertEqual(vm.schemaCatalog.detailedColumnsByTable["users"]?.map(\.name), ["id"])

        await vm.ensureSchemaCatalogLoaded()
        XCTAssertEqual(vm.schemaCatalog.detailedColumnsByTable["users"]?.map(\.name), ["id"],
                       "loading name-only columns must not wipe the detailed columns the ER tab depends on")
        XCTAssertEqual(vm.schemaCatalog.columns(of: "users"), ["id", "name"])
    }

    func testReselectingDatabaseReintrospectsColumns() async {
        let driver = CatalogStub()
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db")
        await vm.ensureSchemaCatalogLoaded()
        XCTAssertEqual(driver.allColumnsCalls, 1)

        await vm.select(database: "db")
        XCTAssertTrue(vm.schemaCatalog.columns(of: "users").isEmpty)
        await vm.ensureSchemaCatalogLoaded()
        XCTAssertEqual(driver.allColumnsCalls, 2)
    }

    func testFailedIntrospectionIsNotCachedAndRetries() async {
        let driver = CatalogStub()
        driver.allColumnsFailNextCall = true
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        await vm.select(database: "db")

        await vm.ensureSchemaCatalogLoaded()
        XCTAssertEqual(driver.allColumnsCalls, 1)
        XCTAssertTrue(vm.schemaCatalog.columns(of: "users").isEmpty)

        await vm.ensureSchemaCatalogLoaded()
        XCTAssertEqual(driver.allColumnsCalls, 2)
        XCTAssertEqual(vm.schemaCatalog.columns(of: "users"), ["id", "name"])
    }

    func testActivityLabelClearsAfterConnectAndBrowse() async {
        let driver = CatalogStub()
        let vm = makeVM(driver)
        await vm.select(profile: .managedMySQL)
        XCTAssertNil(vm.currentActivityLabel)

        await vm.select(database: "db")
        await vm.select(table: TableInfo(name: "users"))
        XCTAssertNil(vm.currentActivityLabel)
    }

    func testActivityLabelShowsConnectingWhileConnecting() async {
        let driver = CatalogStub()
        driver.databasesDelay = .milliseconds(60)
        let vm = makeVM(driver)

        async let connecting: Void = vm.select(profile: .managedMySQL)
        try? await Task.sleep(for: .milliseconds(15))
        XCTAssertEqual(vm.currentActivityLabel, "Connecting…")
        await connecting
        XCTAssertNil(vm.currentActivityLabel)
    }
}
