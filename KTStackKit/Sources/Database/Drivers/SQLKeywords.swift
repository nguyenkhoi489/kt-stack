import Foundation

public enum SQLKeywords {
    public static func forKind(_ kind: DatabaseKind) -> [String] {
        let words: [String] = switch kind {
        case .mysql: common + mysql
        case .postgres: common + postgres
        case .sqlite: common + sqlite
        case .mongodb: common
        }
        return Array(Set(words)).sorted()
    }

    private static let common = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "NULL", "IS", "IN", "LIKE",
        "BETWEEN", "EXISTS", "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET",
        "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "ON", "AS",
        "UNION", "ALL", "DISTINCT", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
        "DELETE", "CREATE", "ALTER", "DROP", "TABLE", "VIEW", "INDEX", "PRIMARY",
        "KEY", "FOREIGN", "REFERENCES", "UNIQUE", "DEFAULT", "CHECK", "CONSTRAINT",
        "CASE", "WHEN", "THEN", "ELSE", "END", "ASC", "DESC", "COUNT", "SUM", "AVG",
        "MIN", "MAX", "CAST", "COALESCE", "WITH", "TRUE", "FALSE",
    ]

    private static let mysql = [
        "AUTO_INCREMENT", "UNSIGNED", "ENGINE", "CHARSET", "COLLATE", "REPLACE",
        "IGNORE", "DUPLICATE", "SHOW", "DESCRIBE", "EXPLAIN", "TINYINT", "INT",
        "BIGINT", "VARCHAR", "TEXT", "DATETIME", "TIMESTAMP", "JSON",
    ]

    private static let postgres = [
        "RETURNING", "SERIAL", "BIGSERIAL", "ILIKE", "BOOLEAN", "JSONB", "UUID",
        "TIMESTAMPTZ", "INTEGER", "VARCHAR", "TEXT", "NUMERIC", "ARRAY", "USING",
        "CONFLICT", "DO", "NOTHING",
    ]

    private static let sqlite = [
        "AUTOINCREMENT", "INTEGER", "REAL", "TEXT", "BLOB", "PRAGMA", "ROWID",
        "WITHOUT", "GLOB", "VACUUM", "ATTACH", "DETACH",
    ]
}
