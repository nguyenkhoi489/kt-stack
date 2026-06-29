import Foundation

public struct DatabaseProvisioner: Sendable {
    public enum ProvisionError: LocalizedError, Equatable {
        case alreadyExists(String)
        public var errorDescription: String? {
            switch self {
            case let .alreadyExists(name):
                "A database named “\(name)” already exists — choose another name."
            }
        }
    }

    private let host: String
    private let port: Int
    private let ensureEngine: @Sendable () async throws -> Void

    public init(
        host: String = "127.0.0.1",
        port: Int = 3306,
        ensureEngine: @escaping @Sendable () async throws -> Void
    ) {
        self.host = host
        self.port = port
        self.ensureEngine = ensureEngine
    }

    public func exists(_ name: String) async throws -> Bool {
        try DumpService.validateIdentifier(name, label: "database")
        try await ensureEngine()
        let result = try await MySQLProbe.run(sql: "SHOW DATABASES", host: host, port: port)
        return result.rows.contains { $0.first.flatMap { $0 } == name }
    }

    public func createDatabase(_ name: String) async throws {
        try DumpService.validateIdentifier(name, label: "database")
        try await ensureEngine()
        if try await exists(name) { throw ProvisionError.alreadyExists(name) }
        let quoted = try SQLDialect.forKind(.mysql).quoteIdent(name)
        _ = try await MySQLProbe.run(sql: "CREATE DATABASE \(quoted)", host: host, port: port)
    }

    public func dropDatabase(_ name: String) async throws {
        try DumpService.validateIdentifier(name, label: "database")
        try await ensureEngine()
        let quoted = try SQLDialect.forKind(.mysql).quoteIdent(name)
        _ = try await MySQLProbe.run(sql: "DROP DATABASE IF EXISTS \(quoted)", host: host, port: port)
    }
}
