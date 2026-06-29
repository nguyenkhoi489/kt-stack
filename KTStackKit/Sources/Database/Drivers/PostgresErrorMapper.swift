import Foundation
import NIOCore
import PostgresNIO

/// Translates PostgresNIO failures into the shared `DatabaseError`. Server errors carry a SQLSTATE
/// (`PSQLError.serverInfo[.sqlState]`); class `28` is "invalid authorization", everything else with a
/// server message is the user's SQL/permission problem. No server response means a transport failure —
/// distinguished as engine-not-running for the managed instance (connection refused) vs a generic
/// connection error for external hosts.
enum PostgresErrorMapper {
    static func map(_ error: any Error, isManaged: Bool) -> DatabaseError {
        if let dbError = error as? DatabaseError { return dbError }
        if let pg = error as? PSQLError {
            if let info = pg.serverInfo {
                let message = info[.message] ?? String(describing: pg)
                if let state = info[.sqlState], state.hasPrefix("28") {
                    return .authenticationFailed(message)
                }
                return .syntax(message)
            }
            return refusedOrGeneric(error, isManaged: isManaged, fallback: String(describing: pg))
        }
        return refusedOrGeneric(error, isManaged: isManaged, fallback: String(describing: error))
    }

    private static func refusedOrGeneric(
        _ error: any Error,
        isManaged: Bool,
        fallback: String
    ) -> DatabaseError {
        if isConnectionRefused(error) {
            return isManaged ? .engineNotRunning(kind: "PostgreSQL") : .connection("Connection refused")
        }
        return .connection(fallback)
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
}
