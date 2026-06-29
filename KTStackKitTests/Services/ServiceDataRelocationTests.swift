import XCTest
@testable import KTStackKit

final class ServiceDataRelocationTests: XCTestCase {
    private func makeTempPaths() -> AppSupportPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-reloc-\(UUID().uuidString)", isDirectory: true)
        return AppSupportPaths(root: root)
    }

    private func installFakeBinary(kind: ServiceKind, version: String, paths: AppSupportPaths) throws {
        let markerRelPath = ServiceBinaryCatalog.marker(kind)!
        let binaryURL = paths.runtimeDir(kind.rawValue, version).appendingPathComponent(markerRelPath)
        try FileManager.default.createDirectory(
            at: binaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: binaryURL.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )
    }

    func testMysqlRelocationAvoidsMovingIntoSelf() throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let catalog = ServiceBinaryCatalog(paths: paths)

        try installFakeBinary(kind: .mysql, version: "9.6.0", paths: paths)

        let flatDir = paths.serviceData("mysql")
        let mysqlSubdir = flatDir.appendingPathComponent("mysql")
        try FileManager.default.createDirectory(at: mysqlSubdir, withIntermediateDirectories: true)
        try Data("ibdata1".utf8).write(to: mysqlSubdir.appendingPathComponent("user.MYD"))

        ServiceDataRelocation.runIfNeeded(paths: paths, catalog: catalog)

        let versionedDir = paths.serviceData("mysql", version: "9.6.0")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: versionedDir.appendingPathComponent("mysql").path),
            "mysql subdir must be under versioned dir"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: flatDir.appendingPathComponent("mysql").path),
            "mysql marker must not remain at flat level"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: flatDir.path),
            "flat dir recreated as version container"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: paths.data.appendingPathComponent("mysql.migrating").path
            ),
            ".migrating must be removed after successful relocation"
        )
    }

    func testPostgresRelocationResumesFromMigrating() throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let catalog = ServiceBinaryCatalog(paths: paths)

        try installFakeBinary(kind: .postgres, version: "17.10", paths: paths)

        let migratingDir = paths.data.appendingPathComponent("postgres.migrating", isDirectory: true)
        try FileManager.default.createDirectory(at: migratingDir, withIntermediateDirectories: true)
        try Data("17".utf8).write(to: migratingDir.appendingPathComponent("PG_VERSION"))

        let flatDir = paths.serviceData("postgres")
        XCTAssertFalse(FileManager.default.fileExists(atPath: flatDir.path))

        ServiceDataRelocation.runIfNeeded(paths: paths, catalog: catalog)

        let versionedDir = paths.serviceData("postgres", version: "17.10")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: versionedDir.appendingPathComponent("PG_VERSION").path),
            "PG_VERSION must be under versioned dir after resume"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: flatDir.path),
            "flat dir recreated during resume"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: migratingDir.path),
            ".migrating cleaned up after resume"
        )
    }

    func testRelocationIsIdempotentWhenVersionedDirExists() throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let catalog = ServiceBinaryCatalog(paths: paths)

        try installFakeBinary(kind: .mysql, version: "9.6.0", paths: paths)

        let versionedDir = paths.serviceData("mysql", version: "9.6.0")
        try FileManager.default.createDirectory(
            at: versionedDir.appendingPathComponent("mysql"),
            withIntermediateDirectories: true
        )

        ServiceDataRelocation.runIfNeeded(paths: paths, catalog: catalog)
        ServiceDataRelocation.runIfNeeded(paths: paths, catalog: catalog)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: versionedDir.appendingPathComponent("mysql").path),
            "versioned data preserved after repeated runs"
        )
    }

    func testEmptyFlatDirSkippedForRedis() throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let catalog = ServiceBinaryCatalog(paths: paths)

        try installFakeBinary(kind: .redis, version: "7.4.2", paths: paths)

        let flatDir = paths.serviceData("redis")
        try FileManager.default.createDirectory(at: flatDir, withIntermediateDirectories: true)

        ServiceDataRelocation.runIfNeeded(paths: paths, catalog: catalog)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.serviceData("redis", version: "7.4.2").path),
            "empty flat dir must not produce a versioned dir"
        )
    }

    func testMailpitNotRelocated() throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let catalog = ServiceBinaryCatalog(paths: paths)

        let mailpitDir = paths.serviceData("mailpit")
        try FileManager.default.createDirectory(at: mailpitDir, withIntermediateDirectories: true)
        try Data().write(to: mailpitDir.appendingPathComponent("mailpit.db"))

        ServiceDataRelocation.runIfNeeded(paths: paths, catalog: catalog)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: mailpitDir.appendingPathComponent("mailpit.db").path),
            "Mailpit data must remain at flat path"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: paths.data.appendingPathComponent("mailpit.migrating").path
            ),
            "no .migrating must be created for mailpit"
        )
    }

    func testSkipsWhenVersionedDirAlreadyExists() throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let catalog = ServiceBinaryCatalog(paths: paths)

        try installFakeBinary(kind: .mysql, version: "9.6.0", paths: paths)

        let versionedDir = paths.serviceData("mysql", version: "9.6.0")
        try FileManager.default.createDirectory(
            at: versionedDir.appendingPathComponent("mysql"),
            withIntermediateDirectories: true
        )

        let flatDir = paths.serviceData("mysql")
        try FileManager.default.createDirectory(
            at: flatDir.appendingPathComponent("mysql"),
            withIntermediateDirectories: true
        )
        try Data("extra".utf8).write(to: flatDir.appendingPathComponent("mysql/extra.txt"))

        ServiceDataRelocation.runIfNeeded(paths: paths, catalog: catalog)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: flatDir.appendingPathComponent("mysql/extra.txt").path),
            "flat data left untouched when versioned dir already exists"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: versionedDir.appendingPathComponent("mysql").path),
            "existing versioned dir preserved"
        )
    }

    func testMongodbRelocationByWiredTigerMarker() throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let catalog = ServiceBinaryCatalog(paths: paths)

        try installFakeBinary(kind: .mongodb, version: "7.0", paths: paths)

        let flatDir = paths.serviceData("mongodb")
        try FileManager.default.createDirectory(at: flatDir, withIntermediateDirectories: true)
        try Data().write(to: flatDir.appendingPathComponent("WiredTiger"))

        ServiceDataRelocation.runIfNeeded(paths: paths, catalog: catalog)

        let versionedDir = paths.serviceData("mongodb", version: "7.0")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: versionedDir.appendingPathComponent("WiredTiger").path),
            "WiredTiger marker must be under versioned dir"
        )
    }
}
