import Foundation
import GRDB

/// Bridges GRDB's `DatabaseValue` storage to the engine-agnostic `Cell`, and `Cell` back to a GRDB
/// bind value. SQLite's storage classes map one-to-one onto `Cell`, so there's no type guessing
/// (unlike text-protocol engines): integer/real/text/blob/null are explicit in the value itself.
enum SQLiteCellMapper {
    static func cell(_ value: DatabaseValue) -> Cell {
        switch value.storage {
        case .null: .null
        case let .int64(i): .int(i)
        case let .double(d): .double(d)
        case let .string(s): .text(s)
        case let .blob(data): .blob(data)
        }
    }

    /// `Cell` → a GRDB-bindable value for `StatementArguments`. `nil` becomes SQL NULL.
    static func bindValue(_ cell: Cell) -> (any DatabaseValueConvertible)? {
        switch cell {
        case let .text(s): s
        case let .int(n): n
        case let .double(d): d
        case let .bool(b): b
        case .null: nil
        case let .blob(data): data
        }
    }

    static func arguments(_ binds: [Cell]) -> StatementArguments {
        StatementArguments(binds.map(bindValue))
    }
}
