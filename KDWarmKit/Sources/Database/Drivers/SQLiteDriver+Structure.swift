import Foundation
import GRDB

/// Schema introspection via GRDB's built-in catalog readers (`PRAGMA table_info` / `index_list`
/// under the hood), mapped into the engine-agnostic shapes the structure view consumes. GRDB's
/// `primaryKeyIndex` is 1-based for primary-key members and 0 otherwise.
extension SQLiteDriver {

    public func columns(database: String, table: String) async throws -> [ColumnInfo] {
        let queue = try makeQueue()
        do {
            return try await queue.read { db in
                try db.columns(in: table).map { info in
                    ColumnInfo(name: info.name,
                               dataType: info.type,
                               isNullable: !info.isNotNull,
                               isPrimaryKey: info.primaryKeyIndex > 0,
                               defaultValue: info.defaultValueSQL)
                }
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    public func indexes(database: String, table: String) async throws -> [IndexInfo] {
        let queue = try makeQueue()
        do {
            return try await queue.read { db in
                try db.indexes(on: table).map { idx in
                    IndexInfo(name: idx.name, columns: idx.columns, isUnique: idx.isUnique)
                }
            }
        } catch {
            throw Self.mapError(error)
        }
    }
}
