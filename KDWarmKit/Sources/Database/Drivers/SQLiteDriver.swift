import Foundation
import GRDB

/// File-based relational driver backed by GRDB. A SQLite "connection" is a `.db` file, so there is no
/// host/port/user — `profile.filePath` is the whole address. GRDB is synchronous with its own
/// serialized queue; we wrap each operation in its async `read`/`write` so the call site stays the
/// same `async` `RelationalDriver` shape as the NIO drivers. Read-only is enforced by opening the file
/// read-only (`Configuration.readonly`), the SQLite-equivalent of a server-side read-only session.
public struct SQLiteDriver: RelationalDriver {
    public let kind: DatabaseKind = .sqlite

    let profile: ConnectionProfile
    let dialect = SQLDialect.forKind(.sqlite)

    public init(profile: ConnectionProfile) {
        self.profile = profile
    }

    /// SQLite's single attached file is its one database; surfaced as `main` so the schema browser's
    /// database → tables flow works unchanged.
    public static let mainDatabase = "main"

    // MARK: - RelationalDriver

    public func ping() async throws {
        let queue = try makeQueue()
        try await queue.read { db in _ = try Int.fetchOne(db, sql: "SELECT 1") }
    }

    public func listDatabases() async throws -> [DatabaseInfo] {
        [DatabaseInfo(name: Self.mainDatabase)]
    }

    public func listTables(database: String) async throws -> [TableInfo] {
        let queue = try makeQueue()
        return try await queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
            SELECT name, type FROM sqlite_master \
            WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY name
            """)
            return rows.compactMap { row in
                guard let name: String = row["name"] else { return nil }
                return TableInfo(name: name, isView: (row["type"] as String?) == "view")
            }
        }
    }

    /// The SQL runner may carry DDL/DML, so a writable connection runs through `write` (which can also
    /// read); a read-only connection uses `read`, where any write attempt fails closed.
    public func query(_ sql: String, database: String?) async throws -> QueryResult {
        let queue = try makeQueue()
        do {
            return profile.readOnly
                ? try await queue.read { try fetch($0, sql: sql, binds: []) }
                : try await queue.write { try fetch($0, sql: sql, binds: []) }
        } catch {
            throw Self.mapError(error)
        }
    }

    public func paginatedRows(database: String, table: String,
                              limit: Int, offset: Int) async throws -> QueryResult {
        let qualified = try dialect.qualifiedTable(schema: database, table: table)
        let sql = dialect.paginate("SELECT * FROM \(qualified)", limit: limit, offset: offset)
        let queue = try makeQueue()
        do {
            return try await queue.read { try fetch($0, sql: sql, binds: []) }
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Shared statement execution

    /// Prepares the statement first so column names survive a zero-row result (the schema browser shows
    /// the header even when a table is empty). A statement with no result columns (DDL/DML) is just
    /// executed; otherwise every row is fetched and its storage classes mapped to `Cell`.
    func fetch(_ db: Database, sql: String, binds: [Cell]) throws -> QueryResult {
        let statement = try db.makeStatement(sql: sql)
        let arguments = SQLiteCellMapper.arguments(binds)
        guard statement.columnCount > 0 else {
            try statement.execute(arguments: arguments)
            return QueryResult(columns: [], rows: [])
        }
        let columns = statement.columnNames.map { ColumnMeta(name: $0) }
        let rows = try Row.fetchAll(statement, arguments: arguments)
        let cells = rows.map { row in
            (0..<row.count).map { SQLiteCellMapper.cell(row[$0] as DatabaseValue) }
        }
        return QueryResult(columns: columns, rows: cells)
    }

    // MARK: - Connection + errors

    func makeQueue() throws -> DatabaseQueue {
        guard let path = profile.filePath, !path.isEmpty else {
            throw DatabaseError.connection("No SQLite file selected for this connection.")
        }
        var config = Configuration()
        config.readonly = profile.readOnly
        do {
            return try DatabaseQueue(path: path, configuration: config)
        } catch {
            throw Self.mapError(error)
        }
    }

    static func mapError(_ error: any Error) -> DatabaseError {
        if let dbError = error as? DatabaseError { return dbError }
        if let grdb = error as? GRDB.DatabaseError {
            let message = grdb.message ?? String(describing: grdb.resultCode)
            // A read-only write attempt and malformed SQL are both surfaced as the user's mistake.
            return grdb.resultCode == .SQLITE_READONLY
                ? .connection("This SQLite database is read-only.")
                : .syntax(message)
        }
        return .connection(String(describing: error))
    }
}
