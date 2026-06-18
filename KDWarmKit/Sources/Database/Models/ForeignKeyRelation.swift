import Foundation

public struct ForeignKeyRelation: Sendable, Hashable, Identifiable {
    public let fromTable: String
    public let fromColumn: String
    public let toTable: String
    public let toColumn: String
    public let constraintName: String?

    public init(fromTable: String,
                fromColumn: String,
                toTable: String,
                toColumn: String,
                constraintName: String? = nil) {
        self.fromTable = fromTable
        self.fromColumn = fromColumn
        self.toTable = toTable
        self.toColumn = toColumn
        self.constraintName = constraintName
    }

    public var id: String {
        "\(constraintName ?? "")|\(fromTable).\(fromColumn)->\(toTable).\(toColumn)"
    }
}
