import Foundation
import MySQLNIO
import NIOCore

final class MySQLSessionConnection: SessionConnection, @unchecked Sendable {
    private let connection: MySQLConnection
    private let isManaged: Bool

    init(connection: MySQLConnection, isManaged: Bool) {
        self.connection = connection
        self.isManaged = isManaged
    }

    var isLive: Bool { !connection.isClosed }

    func runText(_ sql: String) async throws -> QueryResult {
        let command = MySQLTextQueryCommand(sql: sql)
        do {
            try await connection.send(command, logger: connection.logger).get()
        } catch {
            throw MySQLErrorMapper.map(error, isManaged: isManaged)
        }
        let columns = command.columns.map(MySQLCellMapper.columnMeta)
        let rows = command.rows.map { row in
            zip(row.columnDefinitions, row.values).map { MySQLCellMapper.cell(for: $0, value: $1) }
        }
        return QueryResult(columns: columns, rows: rows)
    }

    func runSelect(_ statement: DMLStatement) async throws -> QueryResult {
        let binds = statement.binds.map(MySQLCellMapper.mysqlData(for:))
        do {
            let rows = try await connection.query(statement.sql, binds).get()
            return MySQLCellMapper.result(from: rows)
        } catch {
            throw MySQLErrorMapper.map(error, isManaged: isManaged)
        }
    }

    func shutdown() async {
        try? await connection.close().get()
    }
}
