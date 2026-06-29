import Foundation
import MySQLNIO
import NIOCore

enum MySQLErrorMapper {
    static func map(_ error: any Error, isManaged: Bool) -> DatabaseError {
        if let dbError = error as? DatabaseError { return dbError }
        if let mysql = error as? MySQLError {
            switch mysql {
            case let .invalidSyntax(message): return .syntax(message)
            case let .server(packet):
                switch packet.errorCode {
                case .ACCESS_DENIED_ERROR, .DBACCESS_DENIED_ERROR, .ACCESS_DENIED_NO_PASSWORD_ERROR:
                    return .authenticationFailed(packet.errorMessage)
                default:
                    return .syntax(packet.errorMessage)
                }
            case .closed: return .connection("Connection closed")
            default: return .connection(String(describing: mysql))
            }
        }
        if let channel = error as? ChannelError, case .connectTimeout = channel {
            return .timeout
        }
        if isConnectionRefused(error) {
            return isManaged ? .engineNotRunning(kind: "MySQL") : .connection("Connection refused")
        }
        return .connection(String(describing: error))
    }

    static func isConnectionRefused(_ error: any Error) -> Bool {
        if let io = error as? IOError, io.errnoCode == ECONNREFUSED { return true }
        if let aggregate = error as? NIOConnectionError {
            return aggregate.connectionErrors.contains {
                ($0.error as? IOError)?.errnoCode == ECONNREFUSED
            }
        }
        return false
    }

    static func quoteLiteral(_ value: String) throws -> String {
        guard !value.contains("\u{0}") else {
            throw DatabaseError.connection("Illegal character in SQL literal")
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'"
    }
}
