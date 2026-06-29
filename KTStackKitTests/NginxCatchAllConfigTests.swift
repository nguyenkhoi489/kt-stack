import XCTest
@testable import KTStackKit

final class NginxCatchAllConfigTests: XCTestCase {
    private let writer = NginxConfigWriter()
    private let paths = AppSupportPaths(root: URL(fileURLWithPath: "/tmp/ktstack-catchall-test"))

    func testMasterConfigAlwaysHasPort80CatchAll444() {
        let conf = writer.masterConfig(paths: paths)
        XCTAssertTrue(conf.contains("listen 0.0.0.0:80 default_server;"))
        XCTAssertTrue(conf.contains("server_name _;"))
        XCTAssertTrue(conf.contains("return 444;"))
    }

    func testMasterConfigOmitsSecureCatchAllByDefault() {
        let conf = writer.masterConfig(paths: paths)
        XCTAssertFalse(conf.contains("listen 0.0.0.0:443 ssl default_server;"))
    }

    func testMasterConfigAddsSecureCatchAllWithCertWhenRequested() {
        let conf = writer.masterConfig(paths: paths, secureCatchAll: true)
        XCTAssertTrue(conf.contains("listen 0.0.0.0:443 ssl default_server;"))
        XCTAssertTrue(conf.contains("ssl_certificate \"\(paths.catchAllCert.path)\";"))
        XCTAssertTrue(conf.contains("ssl_certificate_key \"\(paths.catchAllKey.path)\";"))
    }

    func testCatchAllPrecedesSitesInclude() {
        let conf = writer.masterConfig(paths: paths)
        let catchAll = conf.range(of: "default_server")!
        let include = conf.range(of: "include ")!
        XCTAssertTrue(catchAll.lowerBound < include.lowerBound)
    }

    func testEnsureGeneratesParseableSelfSignedCertIdempotently() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-cf-cert-\(UUID().uuidString)")
        let p = AppSupportPaths(root: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cert = NginxCatchAllCert(paths: p)
        XCTAssertFalse(cert.exists())

        let result = try cert.ensure()
        XCTAssertTrue(cert.exists())
        XCTAssertEqual(result.cert, p.catchAllCert)
        let pem = try Data(contentsOf: p.catchAllCert)
        XCTAssertNotNil(CertMinter.notAfter(pem: pem), "openssl cert must be PEM-parseable")
        XCTAssertGreaterThan(CertMinter.notAfter(pem: pem)!, Date(), "cert must not be already expired")

        let again = try cert.ensure()
        XCTAssertEqual(again.cert, result.cert)
    }

    func testGeneratorOmitsSecureCatchAllForNonSecureSites() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-gen-plain-\(UUID().uuidString)")
        let p = AppSupportPaths(root: tmp)
        try p.ensureDirectoryTree()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let site = Site(
            name: "demo",
            path: tmp.path,
            docroot: tmp.path,
            domain: "demo.test",
            phpVersion: "8.4",
            type: .staticSite,
            secure: false
        )
        _ = try SiteConfigGenerator(paths: p).generate(sites: [site])
        let conf = try String(contentsOf: p.nginxConf, encoding: .utf8)
        XCTAssertTrue(conf.contains("listen 0.0.0.0:80 default_server;"))
        XCTAssertFalse(conf.contains("listen 0.0.0.0:443 ssl default_server;"))
        XCTAssertFalse(NginxCatchAllCert(paths: p).exists())
    }

    func testGeneratorAddsSecureCatchAllAndCertForSecureSites() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-gen-secure-\(UUID().uuidString)")
        let p = AppSupportPaths(root: tmp)
        try p.ensureDirectoryTree()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: p.siteCertDir("secure.test"), withIntermediateDirectories: true)
        try "cert".write(to: p.siteCert("secure.test"), atomically: true, encoding: .utf8)
        try "key".write(to: p.siteKey("secure.test"), atomically: true, encoding: .utf8)
        let site = Site(
            name: "secure",
            path: tmp.path,
            docroot: tmp.path,
            domain: "secure.test",
            phpVersion: "8.4",
            type: .staticSite,
            secure: true
        )
        _ = try SiteConfigGenerator(paths: p).generate(sites: [site])
        let conf = try String(contentsOf: p.nginxConf, encoding: .utf8)
        XCTAssertTrue(conf.contains("listen 0.0.0.0:443 ssl default_server;"))
        XCTAssertTrue(NginxCatchAllCert(paths: p).exists())
    }
}
