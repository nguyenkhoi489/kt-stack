import Foundation

public extension RelationalDriver {
    func allColumnsDetailed(database: String) async throws -> [String: [ColumnInfo]] {
        let tables = try await listTables(database: database)
        var map: [String: [ColumnInfo]] = [:]
        for table in tables {
            map[table.name] = try await columns(database: database, table: table.name)
        }
        return map
    }
}
