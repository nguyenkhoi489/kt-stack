import Foundation
import GRDB

final class SQLiteSessionConnection: SessionConnection, @unchecked Sendable {
    private let queue: DatabaseQueue

    init(queue: DatabaseQueue) {
        self.queue = queue
    }

    var isLive: Bool {
        true
    }

    func useDatabase(_: String) async throws {}

    func runText(_ sql: String) async throws -> QueryResult {
        do {
            return try await queue.read { try SQLiteDriver.fetch($0, sql: sql, binds: []) }
        } catch {
            throw SQLiteDriver.mapError(error)
        }
    }

    func runSelect(_ statement: DMLStatement) async throws -> QueryResult {
        do {
            return try await queue.read { try SQLiteDriver.fetch($0, sql: statement.sql, binds: statement.binds) }
        } catch {
            throw SQLiteDriver.mapError(error)
        }
    }

    func shutdown() async {}
}
