import Foundation


public protocol RelationalDriver: DatabaseDriver {

    func listDatabases() async throws -> [DatabaseInfo]

    
    func listTables(database: String) async throws -> [TableInfo]

    func columns(database: String, table: String) async throws -> [ColumnInfo]

    func allColumns(database: String) async throws -> [String: [String]]

    func indexes(database: String, table: String) async throws -> [IndexInfo]

    func foreignKeys(database: String) async throws -> [ForeignKeyRelation]

    func query(_ sql: String, database: String?) async throws -> QueryResult

    func paginatedRows(database: String, table: String, limit: Int, offset: Int) async throws -> QueryResult

    func openSession() async throws

    func closeSession() async

    func runSelect(_ statement: DMLStatement, database: String?) async throws -> QueryResult

    func insert(database: String, table: String, values: [ColumnValue]) async throws

    func update(database: String, table: String, values: [ColumnValue], key: [ColumnValue]) async throws

    func delete(database: String, table: String, key: [ColumnValue]) async throws
}
