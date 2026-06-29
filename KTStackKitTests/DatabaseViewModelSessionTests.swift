import XCTest
@testable import KTStackKit

@MainActor
final class DatabaseViewModelSessionTests: XCTestCase {
    private final class SessionStub: RelationalDriver, @unchecked Sendable {
        let kind: DatabaseKind = .mysql
        let tag: String
        private(set) var openSessionCalls = 0
        private(set) var closeSessionCalls = 0

        init(tag: String) {
            self.tag = tag
        }

        func ping() async throws {}
        func listDatabases() async throws -> [DatabaseInfo] {
            [DatabaseInfo(name: "db_\(tag)")]
        }

        func listTables(database _: String) async throws -> [TableInfo] {
            []
        }

        func columns(database _: String, table _: String) async throws -> [ColumnInfo] {
            []
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
            QueryResult(columns: [], rows: [])
        }

        func openSession() async throws {
            openSessionCalls += 1
        }

        func closeSession() async {
            closeSessionCalls += 1
        }

        func runSelect(_: DMLStatement, database _: String?) async throws -> QueryResult {
            QueryResult(columns: [], rows: [])
        }

        func insert(database _: String, table _: String, values _: [ColumnValue]) async throws {}
        func update(database _: String, table _: String, values _: [ColumnValue], key _: [ColumnValue]) async throws {}
        func delete(database _: String, table _: String, key _: [ColumnValue]) async throws {}
    }

    func testOpensSessionOnceAfterConnecting() async {
        let driver = SessionStub(tag: "a")
        let vm = DatabaseViewModel(makeDriver: { _, _ in driver }, passwordFor: { _ in nil })
        await vm.select(profile: .managedMySQL)
        XCTAssertEqual(driver.openSessionCalls, 1)
    }

    func testReselectingClosesThePreviousSessionAndOpensTheNew() async {
        let first = SessionStub(tag: "a")
        let second = SessionStub(tag: "b")
        var next: SessionStub = first
        let vm = DatabaseViewModel(makeDriver: { _, _ in next }, passwordFor: { _ in nil })

        await vm.select(profile: .managedMySQL)
        XCTAssertEqual(first.openSessionCalls, 1)

        next = second
        await vm.select(profile: .managedMySQL)
        XCTAssertEqual(first.closeSessionCalls, 1)
        XCTAssertEqual(second.openSessionCalls, 1)
    }

    func testFailedConnectionDoesNotOpenSession() async {
        let vm = DatabaseViewModel(makeDriver: { _, _ in nil }, passwordFor: { _ in nil })
        let pg = ConnectionProfile(
            name: "pg",
            kind: .postgres,
            host: "h",
            port: 5432,
            user: "u",
            database: "d"
        )
        await vm.select(profile: pg)
        if case .failed = vm.connection {} else { XCTFail("expected failed connection") }
    }
}
