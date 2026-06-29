import Foundation

public struct DatabaseInfo: Sendable, Hashable, Identifiable {
    public let name: String
    public var id: String {
        name
    }

    public init(name: String) {
        self.name = name
    }
}

public struct TableInfo: Sendable, Hashable, Identifiable {
    public let name: String
    public let isView: Bool
    public var id: String {
        name
    }

    public init(name: String, isView: Bool = false) {
        self.name = name
        self.isView = isView
    }
}

public struct ColumnInfo: Sendable, Hashable, Identifiable {
    public let name: String
    public let dataType: String
    public let isNullable: Bool
    public let isPrimaryKey: Bool
    public let defaultValue: String?

    public var id: String {
        name
    }

    public init(
        name: String,
        dataType: String,
        isNullable: Bool,
        isPrimaryKey: Bool,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.dataType = dataType
        self.isNullable = isNullable
        self.isPrimaryKey = isPrimaryKey
        self.defaultValue = defaultValue
    }
}

public extension [ColumnInfo] {
    var primaryKeyColumns: [ColumnInfo] {
        filter(\.isPrimaryKey)
    }
}

/// One index on a table — grouped from per-column rows so a multi-column index lists every member.
public struct IndexInfo: Sendable, Hashable, Identifiable {
    public let name: String
    public let columns: [String]
    public let isUnique: Bool

    public var id: String {
        name
    }

    public init(name: String, columns: [String], isUnique: Bool) {
        self.name = name
        self.columns = columns
        self.isUnique = isUnique
    }
}

/// A column spec used to compose DDL (CREATE TABLE / ADD COLUMN). Distinct from `ColumnInfo`
/// (which describes an existing column): `type` is a raw SQL type string the dialect sanitizes.
public struct ColumnDefinition: Sendable, Hashable, Identifiable {
    public let name: String
    public let type: String
    public let isNullable: Bool
    public let isPrimaryKey: Bool

    public var id: String {
        name
    }

    public init(name: String, type: String, isNullable: Bool = true, isPrimaryKey: Bool = false) {
        self.name = name
        self.type = type
        self.isNullable = isNullable
        self.isPrimaryKey = isPrimaryKey
    }
}
