import Foundation
import PostgresNIO

/// Schema introspection. Columns join `information_schema.columns` against the table's primary-key
/// constraint so `isPrimaryKey` is accurate (the row-edit gate depends on it); indexes read `pg_catalog`
/// and group per-column rows into one `IndexInfo`. `$1`/`$2` are the schema and table — PostgreSQL
/// reuses a single bind for every reference, so the bind list stays `[schema, table]`.
extension PostgresDriver {

    public func columns(database: String, table: String) async throws -> [ColumnInfo] {
        var binds = PostgresBindings()
        binds.append(database)
        binds.append(table)
        let result = try await runQuery(PostgresQuery(unsafeSQL: """
        SELECT c.column_name, c.data_type, c.is_nullable, c.column_default, \
        CASE WHEN pk.column_name IS NOT NULL THEN 'YES' ELSE 'NO' END AS is_pk \
        FROM information_schema.columns c \
        LEFT JOIN ( \
          SELECT kcu.column_name FROM information_schema.table_constraints tc \
          JOIN information_schema.key_column_usage kcu \
            ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema \
          WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = $1 AND tc.table_name = $2 \
        ) pk ON pk.column_name = c.column_name \
        WHERE c.table_schema = $1 AND c.table_name = $2 ORDER BY c.ordinal_position
        """, binds: binds))
        return result.rows.compactMap { row in
            guard row.count >= 5, let name = row[0].displayText else { return nil }
            return ColumnInfo(
                name: name,
                dataType: row[1].displayText ?? "",
                isNullable: row[2].displayText == "YES",
                isPrimaryKey: row[4].displayText == "YES",
                defaultValue: row[3].displayText)
        }
    }

    public func indexes(database: String, table: String) async throws -> [IndexInfo] {
        var binds = PostgresBindings()
        binds.append(database)
        binds.append(table)
        let result = try await runQuery(PostgresQuery(unsafeSQL: """
        SELECT i.relname AS index_name, a.attname AS column_name, ix.indisunique \
        FROM pg_class t \
        JOIN pg_namespace n ON n.oid = t.relnamespace \
        JOIN pg_index ix ON t.oid = ix.indrelid \
        JOIN pg_class i ON i.oid = ix.indexrelid \
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey) \
        WHERE n.nspname = $1 AND t.relname = $2 \
        ORDER BY i.relname, array_position(ix.indkey, a.attnum)
        """, binds: binds))

        var order: [String] = []
        var grouped: [String: (columns: [String], unique: Bool)] = [:]
        for row in result.rows {
            guard row.count >= 3, let name = row[0].displayText, let column = row[1].displayText
            else { continue }
            let unique = (row[2].displayText ?? "0") == "1"
            if grouped[name] == nil {
                order.append(name)
                grouped[name] = ([], unique)
            }
            grouped[name]?.columns.append(column)
        }
        return order.map { IndexInfo(name: $0, columns: grouped[$0]!.columns, isUnique: grouped[$0]!.unique) }
    }
}
