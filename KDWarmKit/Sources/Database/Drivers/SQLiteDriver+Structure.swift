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

    public func foreignKeys(database: String) async throws -> [ForeignKeyRelation] {
        let queue = try makeQueue()
        do {
            return try await queue.read { db in
                let tableNames = try Row.fetchAll(db, sql: """
                SELECT name FROM sqlite_master \
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name
                """).compactMap { $0["name"] as String? }

                var relations: [ForeignKeyRelation] = []
                for fromTable in tableNames {
                    let pragma = "PRAGMA foreign_key_list(\(Self.quoteIdent(fromTable)))"
                    let rows = try Row.fetchAll(db, sql: pragma)
                    for row in rows {
                        guard let toTable: String = row["table"],
                              let fromColumn: String = row["from"],
                              let toColumn: String = row["to"]
                        else { continue }
                        let id = (row["id"] as Int?).map(String.init)
                        relations.append(ForeignKeyRelation(
                            fromTable: fromTable,
                            fromColumn: fromColumn,
                            toTable: toTable,
                            toColumn: toColumn,
                            constraintName: id))
                    }
                }
                return relations
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    private static func quoteIdent(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
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
