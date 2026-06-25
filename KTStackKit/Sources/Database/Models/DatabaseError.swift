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
        case .engineNotInstalled(let kind): return "The \(kind) engine isn't installed."
        case .engineNotRunning(let kind):   return "The \(kind) engine isn't running."
        case .authenticationFailed(let d):  return "Authentication failed: \(d)"
        case .syntax(let d):                return "SQL error: \(d)"
        case .timeout:                      return "The database operation timed out."
        case .connection(let d):            return "Connection failed: \(d)"
        case .unexpectedResponse(let d):    return "Unexpected database response: \(d)"
        case .cancelled:                    return "Query cancelled."
        }
    }
}

extension DatabaseError: LocalizedError {
    public var errorDescription: String? { message }
}
