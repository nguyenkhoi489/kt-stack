import XCTest
@testable import KDWarmKit

final class NginxTLSVhostWriterTests: XCTestCase {
    private let tls = NginxTLSVhostWriter()
    private let cert = URL(fileURLWithPath: "/ca/certs/app.test/cert.pem")
    private let key = URL(fileURLWithPath: "/ca/certs/app.test/key.pem")

    func testSecurePHPVhostBindsWildcard443WithCertAndFastcgi() {
        let v = tls.secureVhost(domain: "app.test", root: URL(fileURLWithPath: "/site"),
                                certFile: cert, keyFile: key,
                                phpFpmSocket: URL(fileURLWithPath: "/run/php-fpm-8.4.sock"))
        XCTAssertTrue(v.contains("listen 0.0.0.0:443 ssl;"))
        XCTAssertFalse(v.contains("127.0.0.1"))                  // wildcard bind, same rule as :80
        XCTAssertTrue(v.contains("ssl_certificate \"/ca/certs/app.test/cert.pem\";"))
        XCTAssertTrue(v.contains("ssl_certificate_key \"/ca/certs/app.test/key.pem\";"))
        XCTAssertTrue(v.contains("fastcgi_pass \"unix:/run/php-fpm-8.4.sock\";"))
        XCTAssertTrue(v.contains("fastcgi_param HTTPS            on;"))
        // The HTTPS vhost must pass the client address like the :80 vhost, else PHP/Laravel sees an
        // empty REMOTE_ADDR (request()->ip(), rate limiting, logging all break over https).
        XCTAssertTrue(v.contains("fastcgi_param REMOTE_ADDR      $remote_addr;"))
        XCTAssertTrue(v.contains("fastcgi_param REMOTE_PORT      $remote_port;"))
        XCTAssertTrue(v.contains("fastcgi_param SERVER_ADDR      $server_addr;"))
    }

    func testSecureStaticVhostHasNoFastcgi() {
        let v = tls.secureVhost(domain: "html.test", root: URL(fileURLWithPath: "/site"),
                                certFile: cert, keyFile: key, phpFpmSocket: nil)
        XCTAssertTrue(v.contains("listen 0.0.0.0:443 ssl;"))
        XCTAssertFalse(v.contains("fastcgi_pass"))
        XCTAssertTrue(v.contains("try_files $uri $uri/ =404;"))
    }

    func testRedirectVhostSendsHttpToHttps() {
        let r = tls.redirectVhost(domain: "app.test")
        XCTAssertTrue(r.contains("listen 0.0.0.0:80;"))
        XCTAssertTrue(r.contains("return 301 https://$host$request_uri;"))
    }
}

final class MkcertAndCertMinterTests: XCTestCase {
    func testMintArgsTargetCertAndKeyFiles() {
        let args = MkcertRunner.mintArgs(domain: "app.test",
                                         certFile: URL(fileURLWithPath: "/c/cert.pem"),
                                         keyFile: URL(fileURLWithPath: "/c/key.pem"))
        XCTAssertEqual(args, ["-cert-file", "/c/cert.pem", "-key-file", "/c/key.pem", "app.test"])
    }

    func testMintRejectsNonTestDomain() {
        let p = AppSupportPaths(root: URL(fileURLWithPath: "/tmp/kd-x"))
        let minter = CertMinter(paths: p, runner: MkcertRunner(mkcert: p.mkcertBinary, caroot: p.caDir))
        XCTAssertThrowsError(try minter.mint(name: "evil", domain: "evil.com")) { error in
            XCTAssertTrue("\(error)".contains("evil.com"))
        }
    }

    func testPruneOrphansRemovesUnlistedCertDirs() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kd-prune-\(UUID())")
        let p = AppSupportPaths(root: root); try p.ensureDirectoryTree()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: p.siteCertDir("keep.test"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: p.siteCertDir("gone.test"), withIntermediateDirectories: true)
        CertMinter(paths: p, runner: MkcertRunner(mkcert: p.mkcertBinary, caroot: p.caDir))
            .pruneOrphans(keeping: ["keep.test"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: p.siteCertDir("keep.test").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: p.siteCertDir("gone.test").path))
    }

    func testPemExpiryParsesRealMkcertLeaf() throws {
        // Use the Foundations-Spike mkcert leaf if present; else skip (CI without the spike artifact).
        // Repo root derived from this source file: <repo>/KDWarmKitTests/TLSTests.swift.
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let leaf = repoRoot.appendingPathComponent("spikes/s4-mkcert/demo.test.pem")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: leaf.path), "spike leaf not present")
        let pem = try Data(contentsOf: leaf)
        let notAfter = CertMinter.notAfter(pem: pem)
        XCTAssertNotNil(notAfter)
        XCTAssertGreaterThan(notAfter!, Date(), "a freshly-minted leaf must expire in the future")
    }
}

final class SiteConfigGeneratorTLSTests: XCTestCase {
    private let fm = FileManager.default

    private func makePaths() -> (AppSupportPaths, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-tls-\(UUID().uuidString)", isDirectory: true)
        let p = AppSupportPaths(root: root)
        try? p.ensureDirectoryTree()
        return (p, root)
    }

    private func secureSite(_ domain: String) -> Site {
        Site(name: domain, path: "/tmp/\(domain)", docroot: "/tmp/\(domain)/public",
             domain: domain, phpVersion: "8.4", type: .php, secure: true)
    }

    func testSecureSiteWithCertEmitsHttpsAndRedirect() throws {
        let (p, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        let gen = SiteConfigGenerator(paths: p)
        let site = secureSite("app.test")
        // Stage fake leaf files so the generator sees the cert.
        try fm.createDirectory(at: p.siteCertDir(site.domain), withIntermediateDirectories: true)
        try "cert".write(to: p.siteCert(site.domain), atomically: true, encoding: .utf8)
        try "key".write(to: p.siteKey(site.domain), atomically: true, encoding: .utf8)

        let v = gen.vhostText(for: site, port: 80)
        XCTAssertTrue(v.contains("listen 0.0.0.0:443 ssl;"))
        XCTAssertTrue(v.contains("return 301 https://$host$request_uri;"))
    }

    func testSecureSiteWithoutCertFallsBackToHttp() {
        let (p, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        let gen = SiteConfigGenerator(paths: p)
        // secure flag set but NO cert staged → must not emit a broken https vhost.
        let v = gen.vhostText(for: secureSite("nocert.test"), port: 80)
        XCTAssertFalse(v.contains(":443"))
        XCTAssertTrue(v.contains("listen 0.0.0.0:80;"))
    }
}
