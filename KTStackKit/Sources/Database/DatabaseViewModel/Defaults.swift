import Foundation

public extension DatabaseViewModel {
    static let defaultDriver: DriverFactory = { profile, password in
        switch profile.kind {
        case .mysql: MySQLDriver(profile: profile, password: password)
        case .postgres: PostgresDriver(profile: profile, password: password)
        case .sqlite: SQLiteDriver(profile: profile)
        case .mongodb: nil
        }
    }

    static let defaultPassword: @Sendable (ConnectionProfile) -> String? = { profile in
        if profile.isManaged { return nil }
        return try? KeychainStore().get(account: profile.id.uuidString)
    }
}
