import Foundation

public extension DatabaseViewModel {

    static let defaultDriver: DriverFactory = { profile, password in
        switch profile.kind {
        case .mysql:    return MySQLDriver(profile: profile, password: password)
        case .postgres: return PostgresDriver(profile: profile, password: password)
        case .sqlite:   return SQLiteDriver(profile: profile)
        case .mongodb:  return nil
        }
    }

   
    static let defaultPassword: @Sendable (ConnectionProfile) -> String? = { profile in
        if profile.isManaged { return nil }
        return try? KeychainStore().get(account: profile.id.uuidString)
    }
}
