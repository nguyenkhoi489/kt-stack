import XCTest
@testable import KTStackKit

final class ExternalSiteImportTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-import-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    func testLocalSourceParsesPathDomainPhpAndDropsCredentials() throws {
        let support = tmp.appendingPathComponent("Library/Application Support/Local")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let json = """
        {
          "a1": { "name": "Blog", "domain": "blog.local",
                  "path": "\(tmp.path)/sites/blog",
                  "services": { "php": { "version": "8.1.9" } },
                  "mysql": { "user": "root", "password": "supersecret" } }
        }
        """
        try json.write(to: support.appendingPathComponent("sites.json"), atomically: true, encoding: .utf8)

        let sites = LocalSiteSource(home: tmp).discover()
        XCTAssertEqual(sites.count, 1)
        let site = try XCTUnwrap(sites.first)
        XCTAssertEqual(site.domain, "blog.local")
        XCTAssertEqual(site.phpVersion, "8.1")
        XCTAssertEqual(site.path.lastPathComponent, "blog")
        let mirror = "\(site)"
        XCTAssertFalse(mirror.contains("supersecret"), "credentials must never reach DiscoveredSite (H4)")
    }

    func testValetSourceListsParkedDirsWithTLD() throws {
        let config = tmp.appendingPathComponent(".config/valet")
        let parked = tmp.appendingPathComponent("Sites")
        try fm.createDirectory(at: parked.appendingPathComponent("shop"), withIntermediateDirectories: true)
        try fm.createDirectory(at: config.appendingPathComponent("Sites"), withIntermediateDirectories: true)
        try #"{"tld":"test","paths":["\#(parked.path)"]}"#
            .write(to: config.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        let sites = ValetSiteSource(home: tmp).discover()
        XCTAssertTrue(sites.contains { $0.domain == "shop.test" })
    }

    func testMissingToolReturnsEmptyNoCrash() {
        XCTAssertFalse(LocalSiteSource(home: tmp).isAvailable)
        XCTAssertTrue(LocalSiteSource(home: tmp).discover().isEmpty)
        XCTAssertTrue(HerdSiteSource(home: tmp).discover().isEmpty)
        XCTAssertTrue(MAMPSiteSource(root: tmp).discover().isEmpty)
    }

    func testNearestVersionMapsToClosestInstalledWithWarning() {
        let installed = ["8.1", "8.3", "8.4"]
        XCTAssertEqual(ProjectVersionResolver.nearest(to: "8.3", installed: installed)?.exact, true)
        let near = ProjectVersionResolver.nearest(to: "8.2", installed: installed)
        XCTAssertEqual(near?.exact, false)
        XCTAssertTrue(near?.version == "8.1" || near?.version == "8.3")
        XCTAssertEqual(ProjectVersionResolver.nearest(to: "7.4", installed: installed)?.version, "8.1")
    }

    func testDocrootOwnershipRejectsMissingOrUnowned() throws {
        XCTAssertThrowsError(try ImportSafety.resolvedSafeDocroot(tmp.appendingPathComponent("nope")))
        let owned = tmp.appendingPathComponent("ok")
        try fm.createDirectory(at: owned, withIntermediateDirectories: true)
        let resolved = try ImportSafety.resolvedSafeDocroot(owned)
        XCTAssertEqual(resolved.lastPathComponent, "ok")
    }

    func testMAMPVhostParsing() {
        let conf = """
        <VirtualHost *:80>
          ServerName shop.mamp
          DocumentRoot "/Users/x/Sites/shop"
        </VirtualHost>
        """
        let hosts = MAMPSiteSource.parseVirtualHosts(conf)
        XCTAssertEqual(hosts.first?.serverName, "shop.mamp")
        XCTAssertEqual(hosts.first?.docroot, "/Users/x/Sites/shop")
    }
}
