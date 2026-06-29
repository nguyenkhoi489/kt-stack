import Combine
import Foundation

@MainActor
public final class ConnectionStore: ObservableObject {
    @Published public private(set) var profiles: [ConnectionProfile] = []

    public var onChange: (() -> Void)?

    private let storeURL: URL
    private let keychain: KeychainStore

    public init(storeURL: URL, keychain: KeychainStore = KeychainStore()) {
        self.storeURL = storeURL
        self.keychain = keychain
        load()
    }

    public var allProfiles: [ConnectionProfile] {
        [.managedMySQL, .managedPostgres, .managedMongo] + profiles
    }

    public func add(_ profile: ConnectionProfile, password: String? = nil) {
        profiles.append(profile)
        setPassword(password, for: profile)
        persist()
    }

    public func update(_ profile: ConnectionProfile, password: String? = nil) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        setPassword(password, for: profile)
        persist()
    }

    private func setPassword(_ password: String?, for profile: ConnectionProfile) {
        guard let password, !password.isEmpty else { return }
        do {
            try keychain.set(password, account: profile.id.uuidString)
        } catch {
            NSLog("KTStack: failed to store connection password in Keychain: \(error.localizedDescription)")
        }
    }

    public func remove(_ profile: ConnectionProfile) {
        profiles.removeAll { $0.id == profile.id }
        try? keychain.delete(account: profile.id.uuidString)
        persist()
    }

    private func load() {
        defer { onChange?() }
        guard let data = try? Data(contentsOf: storeURL) else { return } // absent file → fresh
        if let decoded = try? JSONDecoder().decode([ConnectionProfile].self, from: data) {
            profiles = decoded
        } else {
            let backup = storeURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: storeURL, to: backup)
            NSLog("KTStack: could not decode connection store; backed up to \(backup.lastPathComponent)")
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            NSLog("KTStack: failed to persist connection store: \(error.localizedDescription)")
        }
        onChange?()
    }
}
