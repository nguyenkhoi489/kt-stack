import Foundation

public enum DatabaseError: Error, Equatable, Sendable {
    case engineNotInstalled(kind: String)

    case engineNotRunning(kind: String)

    case authenticationFailed(String)

    case syntax(String)

    case timeout

    case connection(String)

    case unexpectedResponse(String)

    case cancelled

    public var message: String {
        switch self {
        case let .engineNotInstalled(kind): "The \(kind) engine isn't installed."
        case let .engineNotRunning(kind): "The \(kind) engine isn't running."
        case let .authenticationFailed(d): "Authentication failed: \(d)"
        case let .syntax(d): "SQL error: \(d)"
        case .timeout: "The database operation timed out."
        case let .connection(d): "Connection failed: \(d)"
        case let .unexpectedResponse(d): "Unexpected database response: \(d)"
        case .cancelled: "Query cancelled."
        }
    }
}

extension DatabaseError: LocalizedError {
    public var errorDescription: String? {
        message
    }
}
