import Foundation
import PostgresNIO
import NIOCore
import Logging

final class PostgresSessionConnection: SessionConnection, @unchecked Sendable {
    private let connection: PostgresConnection
    private let logger: Logger
    private let isManaged: Bool

    init(connection: PostgresConnection, logger: Logger, isManaged: Bool) {
        self.connection = connection
        self.logger = logger
        self.isManaged = isManaged
    }

    var isLive: Bool { !connection.isClosed }

    func runText(_ sql: String) async throws -> QueryResult {
        do {
            let rows = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger).collect()
            return PostgresCellMapper.result(from: rows)
        } catch {
            throw PostgresErrorMapper.map(error, isManaged: isManaged)
        }
    }

    func runSelect(_ statement: DMLStatement) async throws -> QueryResult {
        do {
            let query = PostgresQuery(unsafeSQL: statement.sql,
                                      binds: PostgresCellMapper.bindings(statement.binds))
            let rows = try await connection.query(query, logger: logger).collect()
            return PostgresCellMapper.result(from: rows)
        } catch {
            throw PostgresErrorMapper.map(error, isManaged: isManaged)
        }
    }

    func shutdown() async {
        try? await connection.close()
    }
}
