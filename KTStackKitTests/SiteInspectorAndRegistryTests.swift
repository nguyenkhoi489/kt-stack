import XCTest
@testable import KTStackKit

final class SiteInspectorTests: XCTestCase {
    private let inspector = SiteInspector()
    private let fm = FileManager.default

    private func tempFolder(_ name: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testDetectsPublicDocrootAndPHP() throws {
        let folder = tempFolder("laravel")
        defer { try? fm.removeItem(at: folder) }
        let pub = folder.appendingPathComponent("public", isDirectory: true)
        try fm.createDirectory(at: pub, withIntermediateDirectories: true)
        try "<?php".write(to: pub.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)

        let r = inspector.inspect(folder: folder)
        XCTAssertEqual(r.docroot.lastPathComponent, "public")
        XCTAssertEqual(r.type, .php)
        XCTAssertTrue(r.defaultDomain.hasSuffix(".test"))
    }

    func testDetectsPHPWhenEntryIsInstallPHP() throws {
        let folder = tempFolder("wp-install")
        defer { try? fm.removeItem(at: folder) }
        try "<?php".write(to: folder.appendingPathComponent("install.php"), atomically: true, encoding: .utf8)
        XCTAssertEqual(inspector.inspect(folder: folder).type, .php)
    }

    func testDetectsPHPForWordPressInPublicDocroot() throws {
        let folder = tempFolder("wordpress")
        defer { try? fm.removeItem(at: folder) }
        let pub = folder.appendingPathComponent("public", isDirectory: true)
        try fm.createDirectory(at: pub, withIntermediateDirectories: true)
        try "<?php".write(to: pub.appendingPathComponent("wp-load.php"), atomically: true, encoding: .utf8)
        let r = inspector.inspect(folder: folder)
        XCTAssertEqual(r.docroot.lastPathComponent, "public")
        XCTAssertEqual(r.type, .php)
    }

    func testStaticSiteWhenNoPHP() throws {
        let folder = tempFolder("staticsite")
        defer { try? fm.removeItem(at: folder) }
        try "<html>".write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let r = inspector.inspect(folder: folder)
        XCTAssertEqual(r.type, .staticSite)
        XCTAssertEqual(r.docroot, folder) // no public/ → root
    }

    func testNodeWhenPackageJsonAndNoPHP() throws {
        let folder = tempFolder("nodeapp")
        defer { try? fm.removeItem(at: folder) }
        try "{}".write(to: folder.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(inspector.inspect(folder: folder).type, .node)
    }

    func testSlugSanitizesHostnameLabel() {
        XCTAssertEqual(SiteInspector.slug("My Cool App!"), "my-cool-app")
        XCTAssertEqual(SiteInspector.slug("  __  "), "site")
    }
}

@MainActor
final class SiteRegistryTests: XCTestCase {
    private let fm = FileManager.default

    private func makeRegistry() -> (SiteRegistry, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-reg-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return (SiteRegistry(storeURL: dir.appendingPathComponent("sites.json")), dir)
    }

    private func phpFolder(in dir: URL, named: String) throws -> URL {
        let f = dir.appendingPathComponent(named, isDirectory: true)
        let pub = f.appendingPathComponent("public", isDirectory: true)
        try fm.createDirectory(at: pub, withIntermediateDirectories: true)
        try "<?php".write(to: pub.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        return f
    }

    func testAddRegistersSiteAndPersists() throws {
        let (reg, dir) = makeRegistry(); defer { try? fm.removeItem(at: dir) }
        let folder = try phpFolder(in: dir, named: "shop")
        let site = try reg.add(folder: folder)
        XCTAssertEqual(site.domain, "shop.test")
        XCTAssertEqual(site.type, .php)
        XCTAssertEqual(reg.sites.count, 1)

        // A fresh registry over the same store reloads it.
        let reloaded = SiteRegistry(storeURL: dir.appendingPathComponent("sites.json"))
        XCTAssertEqual(reloaded.sites.first?.domain, "shop.test")
    }

    func testAddPersistsDatabaseName() throws {
        let (reg, dir) = makeRegistry(); defer { try? fm.removeItem(at: dir) }
        let site = try reg.add(folder: phpFolder(in: dir, named: "shop"), databaseName: "shop_db")
        XCTAssertEqual(site.databaseName, "shop_db")
        let reloaded = SiteRegistry(storeURL: dir.appendingPathComponent("sites.json"))
        XCTAssertEqual(reloaded.sites.first?.databaseName, "shop_db")
    }

    func testLegacySiteJSONWithoutDatabaseNameDecodesAsNil() throws {
        let (_, dir) = makeRegistry(); defer { try? fm.removeItem(at: dir) }
        let store = dir.appendingPathComponent("sites.json")
        let id = UUID().uuidString
        let legacy = """
        [
          {
            "id": "\(id)",
            "name": "legacy",
            "path": "\(dir.appendingPathComponent("legacy").path)",
            "docroot": "\(dir.appendingPathComponent("legacy/public").path)",
            "domain": "legacy.test",
            "phpVersion": "8.4",
            "type": "php",
            "secure": false
          }
        ]
        """
        try legacy.write(to: store, atomically: true, encoding: .utf8)

        let reloaded = SiteRegistry(storeURL: store)

        XCTAssertEqual(reloaded.sites.count, 1)
        XCTAssertEqual(reloaded.sites.first?.domain, "legacy.test")
        XCTAssertNil(reloaded.sites.first?.databaseName)
    }

    func testRemoveDeletingFolderDeletesFolderAndRegistryEntry() throws {
        let (reg, dir) = makeRegistry(); defer { try? fm.removeItem(at: dir) }
        let folder = try phpFolder(in: dir, named: "shop")
        let site = try reg.add(folder: folder)

        try reg.removeDeletingFolder(site)

        XCTAssertFalse(fm.fileExists(atPath: folder.path))
        XCTAssertTrue(reg.sites.isEmpty)
        let reloaded = SiteRegistry(storeURL: dir.appendingPathComponent("sites.json"))
        XCTAssertTrue(reloaded.sites.isEmpty)
    }

    func testRemoveDeletingFolderRemovesRegistryEntryWhenFolderIsMissing() throws {
        let (reg, dir) = makeRegistry(); defer { try? fm.removeItem(at: dir) }
        let folder = try phpFolder(in: dir, named: "shop")
        let site = try reg.add(folder: folder)
        try fm.removeItem(at: folder)

        try reg.removeDeletingFolder(site)

        XCTAssertTrue(reg.sites.isEmpty)
    }

    func testRemoveDeletingFolderRejectsFilePathAndKeepsRegistryEntry() throws {
        let (reg, dir) = makeRegistry(); defer { try? fm.removeItem(at: dir) }
        let folder = try phpFolder(in: dir, named: "shop")
        let site = try reg.add(folder: folder)
        try fm.removeItem(at: folder)
        try "not a directory".write(to: folder, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try reg.validateCanRemoveFolder(site))
        XCTAssertThrowsError(try reg.removeDeletingFolder(site))
        XCTAssertEqual(reg.sites.count, 1)
    }

    func testDuplicateDefaultDomainGetsSuffix() throws {
        let (reg, dir) = makeRegistry(); defer { try? fm.removeItem(at: dir) }
        _ = try reg.add(folder: phpFolder(in: dir.appendingPathComponent("a", isDirectory: true), named: "blog"))
        let second = try reg.add(folder: phpFolder(in: dir.appendingPathComponent("b", isDirectory: true), named: "blog"))
        XCTAssertEqual(second.domain, "blog-2.test")
    }

    func testDomainValidationRejectsNonTestTLDAndDuplicates() throws {
        let (reg, dir) = makeRegistry(); defer { try? fm.removeItem(at: dir) }
        let site = try reg.add(folder: phpFolder(in: dir, named: "app"))
        XCTAssertThrowsError(try reg.editDomain(site, to: "app.localhost")) // wrong TLD
        XCTAssertThrowsError(try reg.editDomain(site, to: "bad domain.test")) // invalid chars
        let other = try reg.add(folder: phpFolder(in: dir.appendingPathComponent("x", isDirectory: true), named: "other"))
        XCTAssertThrowsError(try reg.editDomain(other, to: "app.test")) // taken
    }

    func testEditDomainAndSetVersionApply() throws {
        let (reg, dir) = makeRegistry(); defer { try? fm.removeItem(at: dir) }
        let site = try reg.add(folder: phpFolder(in: dir, named: "site"))
        try reg.editDomain(site, to: "custom.test")
        reg.setPHPVersion(reg.sites[0], to: "8.1")
        XCTAssertEqual(reg.sites[0].domain, "custom.test")
        XCTAssertEqual(reg.sites[0].phpVersion, "8.1")
    }
}

final class SiteRemovalCoordinatorTests: XCTestCase {
    func testManagedSiteDeletesFolderBeforeDroppingDatabaseAndRemovingRecord() async throws {
        let events = RemovalEvents()
        let coordinator = SiteRemovalCoordinator(
            deleteFolder: { site in await events.append("delete-folder:\(site.domain)") },
            dropDatabase: { database in await events.append("drop-database:\(database)") },
            removeRecord: { site in await events.append("remove-record:\(site.domain)") }
        )
        let site = site(databaseName: "shop_db")

        try await coordinator.remove(site)

        let values = await events.values
        XCTAssertEqual(values, [
            "delete-folder:shop.test",
            "drop-database:shop_db",
            "remove-record:shop.test",
        ])
    }

    func testManualSiteDoesNotDropDatabase() async throws {
        let events = RemovalEvents()
        let coordinator = SiteRemovalCoordinator(
            deleteFolder: { site in await events.append("delete-folder:\(site.domain)") },
            dropDatabase: { database in await events.append("drop-database:\(database)") },
            removeRecord: { site in await events.append("remove-record:\(site.domain)") }
        )
        let site = site(databaseName: nil)

        try await coordinator.remove(site)

        let values = await events.values
        XCTAssertEqual(values, [
            "delete-folder:shop.test",
            "remove-record:shop.test",
        ])
    }

    func testFolderFailureSkipsDatabaseDropAndRecordRemoval() async {
        let events = RemovalEvents()
        let coordinator = SiteRemovalCoordinator(
            deleteFolder: { site in
                await events.append("delete-folder:\(site.domain)")
                throw RemovalFailure.folder
            },
            dropDatabase: { database in await events.append("drop-database:\(database)") },
            removeRecord: { site in await events.append("remove-record:\(site.domain)") }
        )

        do {
            try await coordinator.remove(site(databaseName: "shop_db"))
            XCTFail("expected folder failure")
        } catch {
            XCTAssertEqual(error as? RemovalFailure, .folder)
        }
        let values = await events.values
        XCTAssertEqual(values, ["delete-folder:shop.test"])
    }

    func testDatabaseFailureKeepsRecordForRetryAfterFolderDeletion() async {
        let events = RemovalEvents()
        let coordinator = SiteRemovalCoordinator(
            deleteFolder: { site in await events.append("delete-folder:\(site.domain)") },
            dropDatabase: { database in
                await events.append("drop-database:\(database)")
                throw RemovalFailure.database
            },
            removeRecord: { site in await events.append("remove-record:\(site.domain)") }
        )

        do {
            try await coordinator.remove(site(databaseName: "shop_db"))
            XCTFail("expected database failure")
        } catch {
            XCTAssertEqual(error as? RemovalFailure, .database)
        }
        let values = await events.values
        XCTAssertEqual(values, [
            "delete-folder:shop.test",
            "drop-database:shop_db",
        ])
    }

    private func site(databaseName: String?) -> Site {
        Site(
            name: "shop",
            path: "/tmp/shop",
            docroot: "/tmp/shop/public",
            domain: "shop.test",
            phpVersion: "8.4",
            type: .php,
            databaseName: databaseName
        )
    }
}

private actor RemovalEvents {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

private enum RemovalFailure: Error, Equatable {
    case folder
    case database
}
