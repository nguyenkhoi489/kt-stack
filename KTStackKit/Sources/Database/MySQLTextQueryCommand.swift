import Foundation
import MySQLNIO
import NIOCore

final class MySQLTextQueryCommand: MySQLCommand, @unchecked Sendable {
    private enum State {
        case ready
        case columns(remaining: UInt64)
        case rows
        case done
    }

    let sql: String
    private var state: State = .ready
    private(set) var columns: [MySQLProtocol.ColumnDefinition41] = []
    private(set) var rows: [MySQLRow] = []

    init(sql: String) {
        self.sql = sql
    }

    func activate(capabilities: MySQLProtocol.CapabilityFlags) throws -> MySQLCommandState {
        let query = try MySQLPacket.encode(MySQLProtocol.COM_QUERY(query: sql), capabilities: capabilities)
        return MySQLCommandState(response: [query])
    }

    func handle(
        packet: inout MySQLPacket,
        capabilities: MySQLProtocol.CapabilityFlags
    ) throws -> MySQLCommandState {
        guard !packet.isError else {
            state = .done
            let err = try packet.decode(MySQLProtocol.ERR_Packet.self, capabilities: capabilities)
            switch err.errorCode {
            case .DUP_ENTRY: throw MySQLError.duplicateEntry(err.errorMessage)
            case .PARSE_ERROR: throw MySQLError.invalidSyntax(err.errorMessage)
            default: throw MySQLError.server(err)
            }
        }

        switch state {
        case .ready:
            if packet.isOK {
                state = .done
                return MySQLCommandState(done: true)
            }
            let response = try packet.decode(MySQLProtocol.COM_QUERY_Response.self, capabilities: capabilities)
            state = .columns(remaining: response.columnCount)
            return MySQLCommandState()

        case let .columns(remaining):
            let column = try packet.decode(MySQLProtocol.ColumnDefinition41.self, capabilities: capabilities)
            columns.append(column)

            state = columns.count == numericCast(remaining) ? .rows : .columns(remaining: remaining)
            return MySQLCommandState()

        case .rows:
            guard !packet.isEOF, !packet.isOK else {
                state = .done
                return MySQLCommandState(done: true)
            }
            let data = try MySQLProtocol.TextResultSetRow.decode(from: &packet, columnCount: columns.count)
            rows.append(MySQLRow(format: .text, columnDefinitions: columns, values: data.values))
            return MySQLCommandState()

        case .done:
            throw MySQLError.protocolError
        }
    }
}
