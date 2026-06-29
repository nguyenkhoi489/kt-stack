import Foundation

public extension RelationalDriver {
    func allColumns(database: String) async throws -> [String: [String]] {
        let tables = try await listTables(database: database)
        var map: [String: [String]] = [:]
        for table in tables {
            let cols = try await columns(database: database, table: table.name)
            map[table.name] = cols.map(\.name)
        }
        return map
    }
}
