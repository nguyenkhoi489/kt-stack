import Foundation
import NIOCore
import PostgresNIO

/// Bridges PostgresNIO rows/cells to the engine-agnostic `QueryResult`/`Cell`, and `Cell` to a bind
/// list. PostgreSQL sends every value text-or-binary tagged by its OID, so the cell's `dataType`
/// picks the decode; anything we don't special-case (numeric, timestamps, uuid, json) renders as its
/// text form, which is what the grid displays anyway (numeric stays text to avoid Double precision
/// loss). A `bool` decodes to `Cell.bool`, so the grid shows it as `1`/`0` rather than psql's `t`/`f`.
/// Column names come from each cell (`PostgresRow`
/// doesn't expose its column descriptions publicly), so a zero-row result has no header — acceptable
/// for a browse/SQL surface.
enum PostgresCellMapper {
    static func result(from rows: [PostgresRow]) -> QueryResult {
        guard let first = rows.first else { return QueryResult(columns: [], rows: []) }
        let columns = first.map { ColumnMeta(name: $0.columnName, typeName: String(describing: $0.dataType)) }
        let mapped = rows.map { row in row.map(cell) }
        return QueryResult(columns: columns, rows: mapped)
    }

    static func cell(_ c: PostgresCell) -> Cell {
        guard c.bytes != nil else { return .null }
        switch c.dataType {
        case .bool:
            return (try? c.decode(Bool.self)).map(Cell.bool) ?? text(c)
        case .int2, .int4, .int8:
            return (try? c.decode(Int64.self)).map(Cell.int) ?? text(c)
        case .float4, .float8:
            return (try? c.decode(Double.self)).map(Cell.double) ?? text(c)
        case .bytea:
            if var buffer = try? c.decode(ByteBuffer.self) {
                return .blob(Data(buffer.readBytes(length: buffer.readableBytes) ?? []))
            }
            return text(c)
        default:
            return text(c)
        }
    }

    private static func text(_ c: PostgresCell) -> Cell {
        (try? c.decode(String.self)).map(Cell.text) ?? .null
    }

    static func bindings(_ cells: [Cell]) -> PostgresBindings {
        var binds = PostgresBindings(capacity: cells.count)
        for cell in cells {
            switch cell {
            case let .text(s): binds.append(s)
            case let .int(n): binds.append(n)
            case let .double(d): binds.append(d)
            case let .bool(b): binds.append(b)
            case .null: binds.appendNull()
            case let .blob(data): binds.append(ByteBuffer(bytes: data))
            }
        }
        return binds
    }
}
