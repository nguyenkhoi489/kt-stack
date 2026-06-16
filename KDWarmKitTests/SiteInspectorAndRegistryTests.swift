import XCTest
@testable import KDWarmKit

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
        XCTAssertEqual(r.docroot, folder)   // no public/ → root
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

    func testDuplicateDefaultDomainGetsSuffix() throws {
        let (reg, dir) = makeRegistry(); defer { try? fm.removeItem(at: dir) }
        _ = try reg.add(folder: try phpFolder(in: dir.appendingPathComponent("a", isDirectory: true), named: "blog"))
        let second = try reg.add(folder: try phpFolder(in: dir.appendingPathComponent("b", isDirectory: true), named: "blog"))
        XCTAssertEqual(second.domain, "blog-2.test")
    }

    func testDomainValidationRejectsNonTestTLDAndDuplicates() throws {
        let (reg, dir) = makeRegistry(); defer { try? fm.removeItem(at: dir) }
        let site = try reg.add(folder: try phpFolder(in: dir, named: "app"))
        XCTAssertThrowsError(try reg.editDomain(site, to: "app.localhost"))   // wrong TLD
        XCTAssertThrowsError(try reg.editDomain(site, to: "bad domain.test")) // invalid chars
        let other = try reg.add(folder: try phpFolder(in: dir.appendingPathComponent("x", isDirectory: true), named: "other"))
        XCTAssertThrowsError(try reg.editDomain(other, to: "app.test"))       // taken
    }

    func testEditDomainAndSetVersionApply() throws {
        let (reg, dir) = makeRegistry(); defer { try? fm.removeItem(at: dir) }
        let site = try reg.add(folder: try phpFolder(in: dir, named: "site"))
        try reg.editDomain(site, to: "custom.test")
        reg.setPHPVersion(reg.sites[0], to: "8.1")
        XCTAssertEqual(reg.sites[0].domain, "custom.test")
        XCTAssertEqual(reg.sites[0].phpVersion, "8.1")
    }
}
