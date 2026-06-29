import XCTest
@testable import KTStackKit

/// Persistence coverage for the connection profile store, mirroring `SiteRegistryTests`: profiles
/// round-trip through a temp JSON file, `onChange` fires on every mutation, and a fresh store over
/// the same file reloads them. The synthetic managed profile is always listed but never persisted.
@MainActor
final class ConnectionStoreTests: XCTestCase {
    private let fm = FileManager.default

    /// A store backed by a temp JSON file and a dedicated test-service Keychain (so password assertions
    /// never touch real `com.ktstack.db` credentials). The keychain is returned for read-back + cleanup.
    private func makeStore() -> (ConnectionStore, URL, KeychainStore) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-conn-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let keychain = KeychainStore(service: "com.ktstack.db.tests")
        let store = ConnectionStore(
            storeURL: dir.appendingPathComponent("connections.json"),
            keychain: keychain
        )
        return (store, dir, keychain)
    }

    private func sampleProfile(_ name: String = "prod") -> ConnectionProfile {
        ConnectionProfile(
            name: name,
            kind: .postgres,
            host: "db.example.com",
            port: 5432,
            user: "reader",
            database: "app"
        )
    }

    func testAddPersistsAndReloads() {
        let (store, dir, _) = makeStore(); defer { try? fm.removeItem(at: dir) }
        let profile = sampleProfile()
        store.add(profile)
        XCTAssertTrue(store.profiles.contains(profile))

        let reloaded = ConnectionStore(storeURL: dir.appendingPathComponent("connections.json"))
        XCTAssertTrue(reloaded.profiles.contains(profile))
    }

    func testManagedProfileAlwaysListedButNeverPersisted() throws {
        let (store, dir, _) = makeStore(); defer { try? fm.removeItem(at: dir) }
        // The synthetic managed engine is surfaced in `allProfiles` for the UI...
        XCTAssertTrue(store.allProfiles.contains { $0.isManaged })
        // ...but the on-disk JSON only ever holds user-added profiles.
        store.add(sampleProfile())
        let json = try String(
            decoding: Data(contentsOf: dir.appendingPathComponent("connections.json")),
            as: UTF8.self
        )
        XCTAssertFalse(json.contains("managed"))
    }

    func testUpdateMutatesInPlaceAndPersists() {
        let (store, dir, _) = makeStore(); defer { try? fm.removeItem(at: dir) }
        var profile = sampleProfile()
        store.add(profile)
        profile.name = "renamed"
        store.update(profile)
        XCTAssertEqual(store.profiles.first { $0.id == profile.id }?.name, "renamed")
        XCTAssertEqual(store.profiles.count, 1) // update, not append
    }

    func testRemoveDeletesProfileAndKeychainPassword() throws {
        let (store, dir, keychain) = makeStore(); defer { try? fm.removeItem(at: dir) }
        let profile = sampleProfile()
        store.add(profile, password: "s3cr3t")
        XCTAssertEqual(try keychain.get(account: profile.id.uuidString), "s3cr3t")
        store.remove(profile)
        XCTAssertFalse(store.profiles.contains(profile))
        XCTAssertNil(try keychain.get(account: profile.id.uuidString)) // no orphaned secret
    }

    func testAddStoresPasswordInKeychainNotJSON() throws {
        let (store, dir, keychain) = makeStore(); defer { try? fm.removeItem(at: dir) }
        let profile = sampleProfile()
        defer { try? keychain.delete(account: profile.id.uuidString) }
        store.add(profile, password: "s3cr3t")

        // The password is retrievable from the Keychain...
        XCTAssertEqual(try keychain.get(account: profile.id.uuidString), "s3cr3t")
        // ...but never written to the on-disk JSON.
        let json = try String(
            decoding: Data(contentsOf: dir.appendingPathComponent("connections.json")),
            as: UTF8.self
        )
        XCTAssertFalse(json.contains("s3cr3t"))
        XCTAssertFalse(json.lowercased().contains("password"))
    }

    func testUpdateWithNilPasswordKeepsExistingSecret() throws {
        let (store, dir, keychain) = makeStore(); defer { try? fm.removeItem(at: dir) }
        var profile = sampleProfile()
        defer { try? keychain.delete(account: profile.id.uuidString) }
        store.add(profile, password: "keepme")
        profile.name = "renamed"
        store.update(profile) // no password supplied → existing secret untouched
        XCTAssertEqual(try keychain.get(account: profile.id.uuidString), "keepme")
    }

    func testOnChangeFiresOnMutation() {
        let (store, dir, _) = makeStore(); defer { try? fm.removeItem(at: dir) }
        var fires = 0
        store.onChange = { fires += 1 }
        store.add(sampleProfile())
        store.remove(store.profiles[0])
        XCTAssertEqual(fires, 2)
    }
}
