import Foundation
import PostgresNIO
import NIOCore
import NIOSSL
import Logging

/// Relational driver for PostgreSQL via PostgresNIO. A PG connection is bound to a single database, so
/// the schema browser's "database" maps to a PostgreSQL **schema** (switchable without reconnecting),
/// while the connection's own database comes from the profile. Each operation opens its own connection
/// on the shared event-loop group (mirroring `MySQLDriver`), so results are Sendable and there is no
/// connection-state sharing across the NIO→@MainActor boundary. Read-only is enforced server-side via
/// `default_transaction_read_only`.
public struct PostgresDriver: RelationalDriver {
    public let kind: DatabaseKind = .postgres

    let profile: ConnectionProfile
    let password: String?
    let catalog: ServiceBinaryCatalog
    let dialect = SQLDialect.forKind(.postgres)
    let logger = Logger(label: "kdwarm.postgres")

    public init(profile: ConnectionProfile,
                password: String?,
                catalog: ServiceBinaryCatalog = ServiceBinaryCatalog(paths: AppSupportPaths())) {
        self.profile = profile
        self.password = password
        self.catalog = catalog
    }

    // MARK: - RelationalDriver

    public func ping() async throws {
        _ = try await runQuery(PostgresQuery(unsafeSQL: "SELECT 1"))
    }

    /// Schemas in the connected database stand in for MySQL-style "databases" so the browse flow
    /// (pick a database → list its tables) works unchanged.
    public func listDatabases() async throws -> [DatabaseInfo] {
        let result = try await runQuery(PostgresQuery(unsafeSQL:
            "SELECT schema_name FROM information_schema.schemata ORDER BY schema_name"))
        return result.rows.compactMap { $0.first?.displayText }.map(DatabaseInfo.init(name:))
    }

    public func listTables(database: String) async throws -> [TableInfo] {
        var binds = PostgresBindings()
        binds.append(database)
        let result = try await runQuery(PostgresQuery(unsafeSQL: """
        SELECT table_name, table_type FROM information_schema.tables \
        WHERE table_schema = $1 ORDER BY table_name
        """, binds: binds))
        return result.rows.compactMap { row in
            guard let name = row.first?.displayText else { return nil }
            let isView = row.count > 1 && row[1].displayText == "VIEW"
            return TableInfo(name: name, isView: isView)
        }
    }

    public func query(_ sql: String, database: String?) async throws -> QueryResult {
        try await runQuery(PostgresQuery(unsafeSQL: sql))
    }

    public func paginatedRows(database: String, table: String,
                              limit: Int, offset: Int) async throws -> QueryResult {
        let qualified = try dialect.qualifiedTable(schema: database, table: table)
        let sql = dialect.paginate("SELECT * FROM \(qualified)", limit: limit, offset: offset)
        return try await runQuery(PostgresQuery(unsafeSQL: sql))
    }

    // MARK: - Connect + run

    func runQuery(_ query: PostgresQuery) async throws -> QueryResult {
        try preflightManagedEngine()
        let connection = try await connect()
        do {
            let rows = try await connection.query(query, logger: logger).collect()
            try await connection.close()
            return PostgresCellMapper.result(from: rows)
        } catch {
            try? await connection.close()
            throw PostgresErrorMapper.map(error, isManaged: profile.isManaged)
        }
    }

    func connect() async throws -> PostgresConnection {
        let group = try EventLoopProvider.shared.group()
        let connection: PostgresConnection
        do {
            connection = try await PostgresConnection.connect(
                on: group.next(), configuration: try makeConfiguration(), id: 1, logger: logger)
        } catch {
            throw PostgresErrorMapper.map(error, isManaged: profile.isManaged)
        }
        if profile.readOnly {
            do {
                _ = try await connection.query("SET default_transaction_read_only = on", logger: logger)
            } catch {
                try? await connection.close()
                throw PostgresErrorMapper.map(error, isManaged: profile.isManaged)
            }
        }
        return connection
    }

    func preflightManagedEngine() throws {
        guard profile.isManaged else { return }
        guard catalog.isInstalled(.postgres) else {
            throw DatabaseError.engineNotInstalled(kind: "PostgreSQL")
        }
    }

    private func makeConfiguration() throws -> PostgresConnection.Configuration {
        PostgresConnection.Configuration(
            host: profile.host,
            port: profile.port,
            username: profile.user,
            password: password,
            database: profile.database.isEmpty ? nil : profile.database,
            tls: try makeTLS())
    }

    /// PostgresNIO's TLS has no separate "verify hostname only" tier, so `require`/`verifyFull` both
    /// require TLS and differ only in the certificate-verification policy of the SSL context.
    private func makeTLS() throws -> PostgresConnection.Configuration.TLS {
        var config = TLSConfiguration.makeClientConfiguration()
        switch profile.tlsMode {
        case .disable:
            return .disable
        case .prefer:
            config.certificateVerification = .none
            return .prefer(try NIOSSLContext(configuration: config))
        case .require:
            config.certificateVerification = .noHostnameVerification
            return .require(try NIOSSLContext(configuration: config))
        case .verifyFull:
            config.certificateVerification = .fullVerification
            return .require(try NIOSSLContext(configuration: config))
        }
    }
}
