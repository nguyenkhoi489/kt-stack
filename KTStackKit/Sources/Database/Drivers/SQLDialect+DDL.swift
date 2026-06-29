import Foundation

/// DDL composition. Identifiers are quoted via `quoteIdent` (the injection boundary); column types
/// ride raw because they can't be bound parameters, so `sanitizeType` restricts them to a charset
/// that can't smuggle further DDL. Every generated statement is shown to the user before it runs.
public extension SQLDialect {
    func createTable(schema: String, table: String, columns: [ColumnDefinition]) throws -> String {
        guard !columns.isEmpty else {
            throw DatabaseError.connection("CREATE TABLE needs at least one column")
        }
        let qualified = try qualifiedTable(schema: schema, table: table)
        var defs = try columns.map { try columnClause($0) }
        let primaryKeys = columns.filter(\.isPrimaryKey)
        if !primaryKeys.isEmpty {
            let cols = try primaryKeys.map { try quoteIdent($0.name) }.joined(separator: ", ")
            defs.append("PRIMARY KEY (\(cols))")
        }
        return "CREATE TABLE \(qualified) (\(defs.joined(separator: ", ")))"
    }

    func dropDatabase(_ name: String) throws -> String {
        try "DROP DATABASE \(quoteIdent(name))"
    }

    func dropTable(schema: String, table: String) throws -> String {
        try "DROP TABLE \(qualifiedTable(schema: schema, table: table))"
    }

    func addColumn(schema: String, table: String, column: ColumnDefinition) throws -> String {
        try "ALTER TABLE \(qualifiedTable(schema: schema, table: table)) "
            + "ADD COLUMN \(columnClause(column))"
    }

    func dropColumn(schema: String, table: String, column: String) throws -> String {
        try "ALTER TABLE \(qualifiedTable(schema: schema, table: table)) "
            + "DROP COLUMN \(quoteIdent(column))"
    }

    private func columnClause(_ column: ColumnDefinition) throws -> String {
        let name = try quoteIdent(column.name)
        let type = try Self.sanitizeType(column.type)
        // A PRIMARY KEY column is implicitly NOT NULL in MySQL; emit NOT NULL explicitly for clarity.
        let nullability = (column.isNullable && !column.isPrimaryKey) ? "" : " NOT NULL"
        return "\(name) \(type)\(nullability)"
    }

    /// Column types can't be bound, so allow only a conservative charset: letters, digits, spaces,
    /// parens/comma/dot/underscore (covers `VARCHAR(255)`, `DECIMAL(10,2)`, `UNSIGNED`, etc.). Anything
    /// else (`;`, quotes, backticks, control chars) is rejected so a type string can't extend the DDL.
    static func sanitizeType(_ type: String) throws -> String {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw DatabaseError.connection("Empty column type")
        }
        let allowed = CharacterSet(
            charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 (),._"
        )
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw DatabaseError.connection("Illegal character in column type")
        }
        return trimmed
    }
}
