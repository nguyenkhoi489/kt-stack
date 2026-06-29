import Foundation
import PostgresNIO

/// Row writes. The SQL + binds come from the shared `SQLDialect` (`$N` placeholders for PostgreSQL).
/// Each write runs inside an explicit transaction with `RETURNING 1` so the affected-row count is the
/// number of returned rows — the same "exactly one row" guard the other drivers enforce, rolled back
/// if the count is wrong (also catching a composite-key match that would touch more than one row).
public extension PostgresDriver {
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
        try preflightManagedEngine()
        let connection = try await connect()
        let query = PostgresQuery(
            unsafeSQL: statement.sql + " RETURNING 1",
            binds: PostgresCellMapper.bindings(statement.binds)
        )
        do {
            _ = try await connection.query("BEGIN", logger: logger)
            let affected = try await connection.query(query, logger: logger).collect().count
            guard affected == 1 else {
                _ = try? await connection.query("ROLLBACK", logger: logger)
                try? await connection.close()
                throw DatabaseError.connection(
                    "Affected \(affected) rows; rolled back (expected exactly 1)."
                )
            }
            _ = try await connection.query("COMMIT", logger: logger)
            try await connection.close()
        } catch let error as DatabaseError {
            throw error // guard above already rolled back + closed
        } catch {
            _ = try? await connection.query("ROLLBACK", logger: logger)
            try? await connection.close()
            throw PostgresErrorMapper.map(error, isManaged: profile.isManaged)
        }
    }
}
