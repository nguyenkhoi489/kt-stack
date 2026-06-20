import Foundation
import MySQLNIO
import NIOCore


enum MySQLCellMapper {
    
    private static let stringOrBlobTypes: Set<UInt8> = [
        MySQLProtocol.DataType.tinyBlob.rawValue,
        MySQLProtocol.DataType.mediumBlob.rawValue,
        MySQLProtocol.DataType.longBlob.rawValue,
        MySQLProtocol.DataType.blob.rawValue,
        MySQLProtocol.DataType.varString.rawValue,
        MySQLProtocol.DataType.string.rawValue,
        MySQLProtocol.DataType.varchar.rawValue,
    ]
    private static let integerTypes: Set<UInt8> = [
        MySQLProtocol.DataType.tiny.rawValue,
        MySQLProtocol.DataType.short.rawValue,
        MySQLProtocol.DataType.long.rawValue,
        MySQLProtocol.DataType.int24.rawValue,
        MySQLProtocol.DataType.longlong.rawValue,
        MySQLProtocol.DataType.year.rawValue,
    ]

    private static let floatTypes: Set<UInt8> = [
        MySQLProtocol.DataType.float.rawValue,
        MySQLProtocol.DataType.double.rawValue,
    ]

    static let binaryCharset = MySQLProtocol.CharacterSet.binary.rawValue

    static func isBinary(typeRaw: UInt8, charsetRaw: UInt8) -> Bool {
        stringOrBlobTypes.contains(typeRaw) && charsetRaw == binaryCharset
    }

   
    static func cell(typeRaw: UInt8, charsetRaw: UInt8, value: ByteBuffer?) -> Cell {
        guard var buffer = value else { return .null }

        if isBinary(typeRaw: typeRaw, charsetRaw: charsetRaw) {
            return .blob(Data(buffer.readBytes(length: buffer.readableBytes) ?? []))
        }
        guard let text = buffer.readString(length: buffer.readableBytes) else { return .null }

        if integerTypes.contains(typeRaw) { return Int64(text).map(Cell.int) ?? .text(text) }
        if floatTypes.contains(typeRaw)   { return Double(text).map(Cell.double) ?? .text(text) }
        return .text(text)
    }

    // MARK: - ColumnDefinition41 bridge (driver-side)

    static func cell(for column: MySQLProtocol.ColumnDefinition41, value: ByteBuffer?) -> Cell {
        cell(typeRaw: column.columnType.rawValue, charsetRaw: column.characterSet.rawValue, value: value)
    }


    static func columnMeta(_ column: MySQLProtocol.ColumnDefinition41) -> ColumnMeta {
        ColumnMeta(name: column.name, typeName: column.columnType.description)
    }

    static func result(from rows: [MySQLRow]) -> QueryResult {
        guard let first = rows.first else { return QueryResult(columns: [], rows: []) }
        let columns = first.columnDefinitions.map(columnMeta)
        let mapped = rows.map { row in
            zip(row.columnDefinitions, row.values).map {
                cell(definition: $0, format: row.format, value: $1)
            }
        }
        return QueryResult(columns: columns, rows: mapped)
    }

    static func cell(definition column: MySQLProtocol.ColumnDefinition41,
                     format: MySQLData.Format, value: ByteBuffer?) -> Cell {
        guard let buffer = value else { return .null }
        let typeRaw = column.columnType.rawValue
        if isBinary(typeRaw: typeRaw, charsetRaw: column.characterSet.rawValue) {
            var copy = buffer
            return .blob(Data(copy.readBytes(length: copy.readableBytes) ?? []))
        }
        let data = MySQLData(type: column.columnType, format: format, buffer: buffer,
                             isUnsigned: column.flags.contains(.COLUMN_UNSIGNED))
        if integerTypes.contains(typeRaw) {
            return data.int64.map(Cell.int) ?? data.string.map(Cell.text) ?? .null
        }
        if floatTypes.contains(typeRaw) {
            return data.double.map(Cell.double) ?? data.string.map(Cell.text) ?? .null
        }
        return data.string.map(Cell.text) ?? .null
    }

    // MARK: - Cell → bind value (write path)

    static func mysqlData(for cell: Cell) -> MySQLData {
        switch cell {
        case .text(let s):   return MySQLData(string: s)
        case .int(let n):    return MySQLData(int: Int(n))
        case .double(let d): return MySQLData(double: d)
        case .bool(let b):   return MySQLData(bool: b)
        case .null:          return MySQLData.null
        case .blob(let data):
            var buffer = ByteBufferAllocator().buffer(capacity: data.count)
            buffer.writeBytes(data)
            return MySQLData(type: .blob, format: .binary, buffer: buffer)
        }
    }
}
