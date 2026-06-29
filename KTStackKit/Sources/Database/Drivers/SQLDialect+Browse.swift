import Foundation

public enum FilterOperator: String, Sendable, CaseIterable {
    case equals
    case notEquals
    case contains
    case greaterThan
    case lessThan
    case isNull
    case isNotNull

    public var bindsValue: Bool {
        switch self {
        case .isNull, .isNotNull: false
        default: true
        }
    }
}

public struct FilterCondition: Sendable, Equatable {
    public let column: String
    public let op: FilterOperator
    public let value: Cell

    public init(column: String, op: FilterOperator, value: Cell = .null) {
        self.column = column
        self.op = op
        self.value = value
    }
}

public struct SortSpec: Sendable, Equatable {
    public let column: String
    public let ascending: Bool

    public init(column: String, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }
}

public extension SQLDialect {
    func browseSelect(
        schema: String,
        table: String,
        filters: [FilterCondition],
        sort: SortSpec?,
        limit: Int,
        offset: Int
    ) throws -> DMLStatement {
        let qualified = try qualifiedTable(schema: schema, table: table)
        var sql = "SELECT * FROM \(qualified)"
        var binds: [Cell] = []

        if !filters.isEmpty {
            let clauses = try filters.map { try clause(for: $0, binds: &binds) }
            sql += " WHERE " + clauses.joined(separator: " AND ")
        }

        if let sort {
            try sql += " ORDER BY \(quoteIdent(sort.column)) \(sort.ascending ? "ASC" : "DESC")"
        }

        sql += " LIMIT \(max(1, limit)) OFFSET \(max(0, offset))"
        return DMLStatement(sql: sql, binds: binds)
    }

    private func clause(for filter: FilterCondition, binds: inout [Cell]) throws -> String {
        let column = try quoteIdent(filter.column)
        switch filter.op {
        case .isNull: return "\(column) IS NULL"
        case .isNotNull: return "\(column) IS NOT NULL"
        case .equals: return binary(column, "=", filter.value, &binds)
        case .notEquals: return binary(column, "<>", filter.value, &binds)
        case .greaterThan: return binary(column, ">", filter.value, &binds)
        case .lessThan: return binary(column, "<", filter.value, &binds)
        case .contains:
            binds.append(.text("%\(filter.value.displayText ?? "")%"))
            return "\(column) LIKE \(placeholderStyle.placeholder(binds.count))"
        }
    }

    private func binary(_ column: String, _ op: String, _ value: Cell, _ binds: inout [Cell]) -> String {
        binds.append(value)
        return "\(column) \(op) \(placeholderStyle.placeholder(binds.count))"
    }
}
