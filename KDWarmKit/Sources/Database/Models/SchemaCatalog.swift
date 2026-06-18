import Foundation

public struct SchemaCatalog: Sendable, Equatable {

    public let tables: [String]
    public let columnsByTable: [String: [String]]
    public let relations: [ForeignKeyRelation]

    public init(tables: [String] = [],
                columnsByTable: [String: [String]] = [:],
                relations: [ForeignKeyRelation] = []) {
        self.tables = tables
        self.columnsByTable = columnsByTable
        self.relations = relations
    }

    public static let empty = SchemaCatalog()

    public func withRelations(_ relations: [ForeignKeyRelation]) -> SchemaCatalog {
        SchemaCatalog(tables: tables, columnsByTable: columnsByTable, relations: relations)
    }

    public func columns(of table: String) -> [String] {
        if let exact = columnsByTable[table] { return exact }
        let lower = table.lowercased()
        for (name, cols) in columnsByTable where name.lowercased() == lower {
            return cols
        }
        return []
    }

    public var allColumnNames: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        func absorb(_ cols: [String]) {
            for col in cols where seen.insert(col.lowercased()).inserted {
                ordered.append(col)
            }
        }
        for table in tables { absorb(columns(of: table)) }
        for key in columnsByTable.keys.sorted() where !tables.contains(key) {
            absorb(columnsByTable[key] ?? [])
        }
        return ordered
    }
}
