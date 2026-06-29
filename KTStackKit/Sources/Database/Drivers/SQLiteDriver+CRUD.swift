import Foundation
import GRDB

/// Row writes. The SQL + binds come from the shared `SQLDialect` (positional `?` for SQLite); GRDB's
/// `write` runs them inside a transaction and rolls back automatically if the closure throws — so the
/// "exactly one row" guard (mirroring the other drivers) both reports the anomaly and reverts it.
public extension SQLiteDriver {
    func insert(database: String, table: String, values: [ColumnValue]) async throws {
        try await executeWrite(dialect.insert(schema: database, table: table, values: values))
    }

    func update(
        database: String,
        table: String,
        values: [ColumnValue],
        key: [ColumnValue]
    ) async throws {
        try await executeWrite(dialect.update(schema: database, table: table, values: values, key: key))
    }

    func delete(database: String, table: String, key: [ColumnValue]) async throws {
        try await executeWrite(dialect.delete(schema: database, table: table, key: key))
    }

    private func executeWrite(_ statement: DMLStatement) async throws {
        let queue = try makeQueue()
        do {
            try await queue.write { db in
                try db.execute(
                    sql: statement.sql,
                    arguments: SQLiteCellMapper.arguments(statement.binds)
                )
                let affected = db.changesCount
                guard affected == 1 else {
                    throw DatabaseError.connection(
                        "Affected \(affected) rows; rolled back (expected exactly 1)."
                    )
                }
            }
        } catch {
            throw Self.mapError(error)
        }
    }
}
