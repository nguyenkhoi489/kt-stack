import Foundation

public struct QueryTab: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var sql: String
    public var result: QueryResult?
    public var resultError: String?
    public var isBusy: Bool

    public init(
        id: UUID = UUID(),
        title: String = "Query",
        sql: String = "SELECT 1",
        result: QueryResult? = nil,
        resultError: String? = nil,
        isBusy: Bool = false
    ) {
        self.id = id
        self.title = title
        self.sql = sql
        self.result = result
        self.resultError = resultError
        self.isBusy = isBusy
    }
}
