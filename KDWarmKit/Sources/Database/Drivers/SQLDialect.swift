import Foundation

/// How a dialect spells a bound-parameter placeholder. MySQL and SQLite (GRDB) use positional `?`;
/// PostgreSQL numbers them `$1, $2, …`. The number is the parameter's 1-based position in the bind
/// array, so a single running index across an UPDATE's SET + WHERE clauses lines up with `binds`.
public enum PlaceholderStyle: Sendable {
    case question
    case dollar

    func placeholder(_ oneBasedIndex: Int) -> String {
        switch self {
        case .question: return "?"
        case .dollar:   return "$\(oneBasedIndex)"
        }
    }
}

public struct SQLDialect: Sendable {

    public let quote: Character
    public let placeholderStyle: PlaceholderStyle

    public static func forKind(_ kind: DatabaseKind) -> SQLDialect {
        switch kind {
        case .mysql:            return SQLDialect(quote: "`",  placeholderStyle: .question)
        case .postgres:         return SQLDialect(quote: "\"", placeholderStyle: .dollar)
        case .sqlite, .mongodb: return SQLDialect(quote: "\"", placeholderStyle: .question)
        }
    }

  
    public func quoteIdent(_ identifier: String) throws -> String {
        guard !identifier.isEmpty else {
            throw DatabaseError.connection("Empty SQL identifier")
        }
        guard !identifier.contains("\u{0}"), !identifier.contains(where: \.isNewline) else {
            throw DatabaseError.connection("Illegal character in SQL identifier")
        }
        let escaped = identifier.replacingOccurrences(of: String(quote), with: String(repeating: quote, count: 2))
        return "\(quote)\(escaped)\(quote)"
    }

   
    public func qualifiedTable(schema: String, table: String) throws -> String {
        "\(try quoteIdent(schema)).\(try quoteIdent(table))"
    }


    public func paginate(_ sql: String, limit: Int, offset: Int) -> String {
        let safeLimit = max(1, limit)
        let safeOffset = max(0, offset)
        return "\(sql) LIMIT \(safeLimit) OFFSET \(safeOffset)"
    }

    // MARK: - DML composition (parameterized)

    public func insert(schema: String, table: String, values: [ColumnValue]) throws -> DMLStatement {
        guard !values.isEmpty else {
            throw DatabaseError.connection("INSERT needs at least one column")
        }
        let qualified = try qualifiedTable(schema: schema, table: table)
        let columns = try values.map { try quoteIdent($0.column) }.joined(separator: ", ")
        let placeholders = (1...values.count)
            .map { placeholderStyle.placeholder($0) }.joined(separator: ", ")
        return DMLStatement(sql: "INSERT INTO \(qualified) (\(columns)) VALUES (\(placeholders))",
                            binds: values.map(\.value))
    }

 
    public func update(schema: String, table: String,
                       values: [ColumnValue], key: [ColumnValue]) throws -> DMLStatement {
        guard !values.isEmpty else {
            throw DatabaseError.connection("UPDATE needs at least one column to set")
        }
        try requireUsableKey(key)
        let qualified = try qualifiedTable(schema: schema, table: table)
        var index = 0
        let setClause = try values.map { col -> String in
            index += 1
            return "\(try quoteIdent(col.column)) = \(placeholderStyle.placeholder(index))"
        }.joined(separator: ", ")
        let whereClause = try key.map { col -> String in
            index += 1
            return "\(try quoteIdent(col.column)) = \(placeholderStyle.placeholder(index))"
        }.joined(separator: " AND ")
        return DMLStatement(sql: "UPDATE \(qualified) SET \(setClause) WHERE \(whereClause)",
                            binds: values.map(\.value) + key.map(\.value))
    }


    public func delete(schema: String, table: String, key: [ColumnValue]) throws -> DMLStatement {
        try requireUsableKey(key)
        let qualified = try qualifiedTable(schema: schema, table: table)
        var index = 0
        let whereClause = try key.map { col -> String in
            index += 1
            return "\(try quoteIdent(col.column)) = \(placeholderStyle.placeholder(index))"
        }.joined(separator: " AND ")
        return DMLStatement(sql: "DELETE FROM \(qualified) WHERE \(whereClause)",
                            binds: key.map(\.value))
    }

    private func requireUsableKey(_ key: [ColumnValue]) throws {
        guard !key.isEmpty else {
            throw DatabaseError.connection("Refusing an UPDATE/DELETE with no key (would affect every row)")
        }
        guard !key.contains(where: { $0.value == .null }) else {
            throw DatabaseError.connection("A NULL key can't identify a single row")
        }
    }
}


public struct DMLStatement: Sendable, Equatable {
    public let sql: String
    public let binds: [Cell]

    public init(sql: String, binds: [Cell]) {
        self.sql = sql
        self.binds = binds
    }
}
