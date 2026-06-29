import Foundation

public enum TLSMode: String, Codable, Sendable, CaseIterable {
    case disable
    case prefer
    case require
    case verifyFull

    public static func defaultMode(forHost host: String) -> TLSMode {
        ConnectionProfile.isLoopback(host) ? .prefer : .verifyFull
    }
}

public enum DatabaseKind: String, Codable, Sendable, CaseIterable {
    case mysql
    case postgres
    case sqlite
    case mongodb
}

public struct ConnectionProfile: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var kind: DatabaseKind
    public var host: String
    public var port: Int
    public var user: String
    public var database: String

    public var filePath: String?
    public var tlsMode: TLSMode

    public var readOnly: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        kind: DatabaseKind,
        host: String,
        port: Int,
        user: String,
        database: String,
        filePath: String? = nil,
        tlsMode: TLSMode? = nil,
        readOnly: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.user = user
        self.database = database
        self.filePath = filePath
        self.tlsMode = tlsMode ?? .defaultMode(forHost: host)
        self.readOnly = readOnly ?? Self.defaultReadOnly(forHost: host)
    }

    public static func isLoopback(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "::1" || host == "localhost"
    }

    public static func defaultReadOnly(forHost host: String) -> Bool {
        !isLoopback(host)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, host, port, user, database, filePath, tlsMode, readOnly
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(UUID.self, forKey: .id),
            name: c.decode(String.self, forKey: .name),
            kind: c.decode(DatabaseKind.self, forKey: .kind),
            host: c.decode(String.self, forKey: .host),
            port: c.decode(Int.self, forKey: .port),
            user: c.decode(String.self, forKey: .user),
            database: c.decode(String.self, forKey: .database),
            filePath: c.decodeIfPresent(String.self, forKey: .filePath),
            tlsMode: c.decodeIfPresent(TLSMode.self, forKey: .tlsMode),
            readOnly: c.decodeIfPresent(Bool.self, forKey: .readOnly)
        )
    }

    public static let managedMySQL = ConnectionProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "MySQL (managed)",
        kind: .mysql,
        host: "127.0.0.1",
        port: 3306,
        user: "root",
        database: "mysql",
        tlsMode: .prefer,
        readOnly: false
    )

    /// The managed PostgreSQL instance: loopback, trust auth (`initdb -U postgres --auth=trust`), so no
    /// password and no TLS. Like the managed MySQL row it always appears in the sidebar; connecting
    /// fails cleanly when the engine isn't installed/running.
    public static let managedPostgres = ConnectionProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "PostgreSQL (managed)",
        kind: .postgres,
        host: "127.0.0.1",
        port: 5432,
        user: "postgres",
        database: "postgres",
        tlsMode: .disable,
        readOnly: false
    )

    public static let managedMongo = ConnectionProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "MongoDB (managed)",
        kind: .mongodb,
        host: "127.0.0.1",
        port: 27017,
        user: "",
        database: "admin",
        tlsMode: .disable,
        readOnly: false
    )

    public var isManaged: Bool {
        id == Self.managedMySQL.id || id == Self.managedPostgres.id || id == Self.managedMongo.id
    }
}
