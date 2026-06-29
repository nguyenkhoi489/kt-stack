import Foundation
import MySQLNIO
import NIOCore

public extension MySQLDriver {
    func insert(database: String, table: String, values: [ColumnValue]) async throws {
        let statement = try dialect.insert(schema: database, table: table, values: values)
        try await executeWrite(statement, database: database)
    }

    func update(
        database: String,
        table: String,
        values: [ColumnValue],
        key: [ColumnValue]
    ) async throws {
        let statement = try dialect.update(schema: database, table: table, values: values, key: key)
        try await executeWrite(statement, database: database)
    }

    func delete(database: String, table: String, key: [ColumnValue]) async throws {
        let statement = try dialect.delete(schema: database, table: table, key: key)
        try await executeWrite(statement, database: database)
    }

    private func executeWrite(_ statement: DMLStatement, database: String) async throws {
        try preflightManagedEngine()
        let connection = try await connect(database: database)
        do {
            _ = try await connection.simpleQuery("START TRANSACTION").get()
            let affected = AffectedRowsBox()
            let binds = statement.binds.map(MySQLCellMapper.mysqlData(for:))
            _ = try await connection.query(
                statement.sql,
                binds,
                onMetadata: { affected.value = $0.affectedRows }
            ).get()
            guard affected.value == 1 else {
                _ = try? await connection.simpleQuery("ROLLBACK").get()
                try? await connection.close().get()
                throw DatabaseError.connection(
                    "Affected \(affected.value) rows; rolled back (expected exactly 1)."
                )
            }
            _ = try await connection.simpleQuery("COMMIT").get()
            try await connection.close().get()
        } catch let error as DatabaseError {
            throw error // already mapped + connection handled above
        } catch {
            _ = try? await connection.simpleQuery("ROLLBACK").get()
            try? await connection.close().get()
            throw MySQLErrorMapper.map(error, isManaged: profile.isManaged)
        }
    }
}

private final class AffectedRowsBox: @unchecked Sendable {
    var value: UInt64 = 0
}
