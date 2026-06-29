import Foundation

public enum BackupProviderResult: Sendable {
    case available(BackupProvider)
    case unavailable(reason: String)
}

public enum BackupProviderFactory {
    public static func make(for kind: DatabaseKind) -> BackupProviderResult {
        switch kind {
        case .mysql:
            wrap(
                MySQLBackupProvider(),
                unavailable: "The MySQL client tools (mysqldump/mysql) aren't installed."
            )
        case .postgres:
            wrap(
                PostgresBackupProvider(),
                unavailable: "The PostgreSQL client tools (pg_dump/pg_restore) aren't installed."
            )
        case .sqlite:
            .available(SQLiteBackupProvider())
        case .mongodb:
            wrap(
                MongoBackupProvider(),
                unavailable: "The MongoDB database tools (mongodump/mongorestore) aren't installed."
            )
        }
    }

    public static func provider(for kind: DatabaseKind) -> BackupProvider? {
        if case let .available(provider) = make(for: kind) { return provider }
        return nil
    }

    private static func wrap(_ provider: BackupProvider, unavailable: String) -> BackupProviderResult {
        provider.isAvailable ? .available(provider) : .unavailable(reason: unavailable)
    }
}
