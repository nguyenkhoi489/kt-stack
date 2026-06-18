import Foundation

public struct QueryHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sql: String
    public let ranAt: Date
    public let connectionLabel: String
    public let database: String?

    public init(
        id: UUID = UUID(),
        sql: String,
        ranAt: Date = Date(),
        connectionLabel: String,
        database: String?
    ) {
        self.id = id
        self.sql = sql
        self.ranAt = ranAt
        self.connectionLabel = connectionLabel
        self.database = database
    }
}
