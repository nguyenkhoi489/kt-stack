import Foundation

public extension DocumentViewModel {
    static let defaultDriver: DriverFactory = { profile, password in
        switch profile.kind {
        case .mongodb: MongoDriver(profile: profile, password: password)
        case .mysql, .postgres, .sqlite: nil
        }
    }

    static let defaultPassword: @Sendable (ConnectionProfile) -> String? = { profile in
        if profile.isManaged { return nil }
        return try? KeychainStore().get(account: profile.id.uuidString)
    }
}
