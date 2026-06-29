import XCTest
@testable import KTStackKit

final class ServerListAndLastUsedDatabaseTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "ktstack.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testLastUsedDatabaseRoundTripsPerProfile() {
        let store = LastUsedDatabaseStore(defaults: makeDefaults())
        let a = UUID()
        let b = UUID()
        XCTAssertNil(store.lastDatabase(for: a))
        store.setLastDatabase("shop", for: a)
        store.setLastDatabase("analytics", for: b)
        XCTAssertEqual(store.lastDatabase(for: a), "shop")
        XCTAssertEqual(store.lastDatabase(for: b), "analytics")
    }

    func testLastUsedDatabaseClearsOnNilOrEmpty() {
        let store = LastUsedDatabaseStore(defaults: makeDefaults())
        let id = UUID()
        store.setLastDatabase("shop", for: id)
        store.setLastDatabase(nil, for: id)
        XCTAssertNil(store.lastDatabase(for: id))
        store.setLastDatabase("shop", for: id)
        store.setLastDatabase("", for: id)
        XCTAssertNil(store.lastDatabase(for: id))
    }

    func testProbeOutcomeMapsToStatus() {
        XCTAssertEqual(ServerReachabilityService.map(.managed(running: true)), .online)
        XCTAssertEqual(ServerReachabilityService.map(.managed(running: false)), .offline)
        XCTAssertEqual(ServerReachabilityService.map(.file(exists: true)), .online)
        XCTAssertEqual(ServerReachabilityService.map(.file(exists: false)), .offline)
        XCTAssertEqual(ServerReachabilityService.map(.tcp(reachable: true)), .online)
        XCTAssertEqual(ServerReachabilityService.map(.tcp(reachable: false)), .offline)
    }

    func testManagedProfileResolvesViaServiceState() {
        let outcome = ServerReachabilityService.outcome(
            for: .managedMySQL, managedRunning: false, tcpReachable: true, fileExists: false
        )
        XCTAssertEqual(outcome, .managed(running: false))
        XCTAssertEqual(ServerReachabilityService.map(outcome), .offline)
    }

    func testSQLiteProfileResolvesViaFileExistence() {
        let profile = ConnectionProfile(
            name: "local",
            kind: .sqlite,
            host: "",
            port: 0,
            user: "",
            database: "main",
            filePath: "/tmp/missing.sqlite"
        )
        let outcome = ServerReachabilityService.outcome(
            for: profile, managedRunning: true, tcpReachable: true, fileExists: false
        )
        XCTAssertEqual(outcome, .file(exists: false))
    }

    @MainActor
    func testResolvePreferredDatabasePrecedence() {
        let store = LastUsedDatabaseStore(defaults: makeDefaults())
        let vm = DatabaseViewModel(lastUsedStore: store)
        let profile = ConnectionProfile(
            name: "srv",
            kind: .mysql,
            host: "127.0.0.1",
            port: 3306,
            user: "root",
            database: "app"
        )
        vm.databases = [DatabaseInfo(name: "alpha"), DatabaseInfo(name: "app"), DatabaseInfo(name: "shop")]

        XCTAssertEqual(vm.resolvePreferredDatabase(for: profile), "app")

        store.setLastDatabase("shop", for: profile.id)
        XCTAssertEqual(vm.resolvePreferredDatabase(for: profile), "shop")

        store.setLastDatabase("vanished", for: profile.id)
        XCTAssertEqual(vm.resolvePreferredDatabase(for: profile), "app")

        vm.databases = []
        XCTAssertNil(vm.resolvePreferredDatabase(for: profile))
    }

    func testRemoteProfileResolvesViaTCP() {
        let profile = ConnectionProfile(
            name: "remote",
            kind: .mysql,
            host: "db.example.com",
            port: 3306,
            user: "root",
            database: "app"
        )
        let outcome = ServerReachabilityService.outcome(
            for: profile, managedRunning: true, tcpReachable: false, fileExists: true
        )
        XCTAssertEqual(outcome, .tcp(reachable: false))
        XCTAssertEqual(ServerReachabilityService.map(outcome), .offline)
    }
}
