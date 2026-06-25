import Foundation

public enum Cell: Sendable, Equatable {
    case text(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case null
    case blob(Data)

    public var displayText: String? {
        switch self {
        case .text(let s):   return s
        case .int(let n):    return String(n)
        case .double(let d): return String(d)
        case .bool(let b):   return b ? "1" : "0"
        case .null:          return nil
        case .blob(let d):   return "[\(d.count) bytes]"
        }
    }
}

public struct ColumnMeta: Sendable, Equatable {
    public let name: String
    public let typeName: String?

    public init(name: String, typeName: String? = nil) {
        self.name = name
        self.typeName = typeName
    }
}

public struct QueryResult: Sendable, Equatable {
    public let columns: [ColumnMeta]
    public let rows: [[Cell]]
    public let truncated: Bool
    public let estimatedTotal: Int?

    public init(columns: [ColumnMeta], rows: [[Cell]],
                truncated: Bool = false, estimatedTotal: Int? = nil) {
        self.columns = columns
        self.rows = rows
        self.truncated = truncated
        self.estimatedTotal = estimatedTotal
    }

    public var rowCount: Int { rows.count }
    public var columnNames: [String] { columns.map(\.name) }

    public static func == (lhs: QueryResult, rhs: QueryResult) -> Bool {
        lhs.columns == rhs.columns && lhs.rows == rhs.rows
    }
}


public struct ColumnValue: Sendable, Equatable {
    public let column: String
    public let value: Cell

    public init(column: String, value: Cell) {
        self.column = column
        self.value = value
    }
}
