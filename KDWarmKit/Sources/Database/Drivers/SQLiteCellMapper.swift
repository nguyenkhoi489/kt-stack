import Foundation
import GRDB

/// Bridges GRDB's `DatabaseValue` storage to the engine-agnostic `Cell`, and `Cell` back to a GRDB
/// bind value. SQLite's storage classes map one-to-one onto `Cell`, so there's no type guessing
/// (unlike text-protocol engines): integer/real/text/blob/null are explicit in the value itself.
enum SQLiteCellMapper {

    static func cell(_ value: DatabaseValue) -> Cell {
        switch value.storage {
        case .null:            return .null
        case .int64(let i):    return .int(i)
        case .double(let d):   return .double(d)
        case .string(let s):   return .text(s)
        case .blob(let data):  return .blob(data)
        }
    }

    /// `Cell` → a GRDB-bindable value for `StatementArguments`. `nil` becomes SQL NULL.
    static func bindValue(_ cell: Cell) -> (any DatabaseValueConvertible)? {
        switch cell {
        case .text(let s):    return s
        case .int(let n):     return n
        case .double(let d):  return d
        case .bool(let b):    return b
        case .null:           return nil
        case .blob(let data): return data
        }
    }

    static func arguments(_ binds: [Cell]) -> StatementArguments {
        StatementArguments(binds.map(bindValue))
    }
}
