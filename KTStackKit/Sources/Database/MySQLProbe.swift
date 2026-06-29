import Foundation
import MySQLNIO
import NIOCore
import NIOSSL

public struct QueryResultSet: Sendable, Equatable {
    public let columns: [String]
    public let rows: [[String?]]

    public init(columns: [String], rows: [[String?]]) {
        self.columns = columns
        self.rows = rows
    }

    public var rowCount: Int {
        rows.count
    }

    public init(columns: [String], textRows: [MySQLRow]) {
        self.columns = columns
        rows = textRows.map { Self.textCells($0.values) }
    }

    public static func textCells(_ values: [ByteBuffer?]) -> [String?] {
        values.map { buffer in
            guard var buffer else { return nil }
            return buffer.readString(length: buffer.readableBytes)
        }
    }
}

public enum MySQLProbe {
    public static var loopbackTLS: TLSConfiguration {
        var config = TLSConfiguration.makeClientConfiguration()
        config.certificateVerification = .none
        return config
    }

    static func isLoopback(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "::1" || host == "localhost"
    }

    static func defaultTLS(forHost host: String) -> TLSConfiguration {
        isLoopback(host) ? loopbackTLS : .makeClientConfiguration()
    }

    public static func run(
        sql: String,
        host: String = "127.0.0.1",
        port: Int = 3306,
        username: String = "root",
        password: String? = nil,
        database: String = "mysql",
        tlsConfiguration: TLSConfiguration? = nil
    ) async throws -> QueryResultSet {
        let tls = tlsConfiguration ?? defaultTLS(forHost: host)
        let group = try EventLoopProvider.shared.group()
        let address = try SocketAddress.makeAddressResolvingHost(host, port: port)
        let connection = try await MySQLConnection.connect(
            to: address,
            username: username,
            database: database,
            password: password,
            tlsConfiguration: tls,
            on: group.next()
        ).get()

        let command = MySQLTextQueryCommand(sql: sql)
        do {
            try await connection.send(command, logger: connection.logger).get()
        } catch {
            try? await connection.close().get()
            throw error
        }

        try await connection.close().get()
        return QueryResultSet(columns: command.columns.map(\.name), textRows: command.rows)
    }
}
