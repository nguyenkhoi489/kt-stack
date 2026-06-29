import XCTest
@testable import KTStackKit

final class LegacyKDWarmMigrationTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kt-mig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testRelocateMovesLegacyRootWhenNewIsAbsent() throws {
        let base = try tempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appendingPathComponent("KDWarm", isDirectory: true)
        let new = base.appendingPathComponent("KTStack", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("sites".utf8).write(to: legacy.appendingPathComponent("sites.json"))

        XCTAssertTrue(LegacyKDWarmMigration.relocateDataDirectory(from: legacy, to: new))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.appendingPathComponent("sites.json").path))
    }

    func testRelocateDoesNotClobberExistingNewRoot() throws {
        let base = try tempDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appendingPathComponent("KDWarm", isDirectory: true)
        let new = base.appendingPathComponent("KTStack", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)

        XCTAssertFalse(LegacyKDWarmMigration.relocateDataDirectory(from: legacy, to: new))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testPurgeRemovesLegacyLaunchPlistsOnly() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppSupportPaths(root: root)
        try FileManager.default.createDirectory(at: paths.launchAgents, withIntermediateDirectories: true)
        let legacyPlist = paths.launchAgents.appendingPathComponent("com.kdwarm.nginx.plist")
        let keptPlist = paths.launchAgents.appendingPathComponent("com.ktstack.nginx.plist")
        try Data().write(to: legacyPlist)
        try Data().write(to: keptPlist)

        LegacyKDWarmMigration.purgeLegacyLaunchPlists(in: paths)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPlist.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptPlist.path))
    }

    func testKeychainServiceMigrationRoundTrips() throws {
        let oldService = "com.ktstack.test.legacy.\(UUID().uuidString)"
        let newService = "com.ktstack.test.new.\(UUID().uuidString)"
        let source = KeychainStore(service: oldService)
        let destination = KeychainStore(service: newService)
        defer {
            try? source.delete(account: "db1")
            try? destination.delete(account: "db1")
        }
        try source.set("secret-pw", account: "db1")

        KeychainStore.migrateService(from: oldService, to: newService)

        XCTAssertEqual(try destination.get(account: "db1"), "secret-pw")
        XCTAssertNil(try source.get(account: "db1"))
    }
}
