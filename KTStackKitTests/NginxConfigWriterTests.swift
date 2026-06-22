import XCTest
@testable import KTStackKit

/// The load-bearing invariant of the HTTP slice: generated vhosts MUST listen on the
/// wildcard `0.0.0.0` (bindable without root) and NEVER on a specific loopback interface
/// (`127.0.0.1`, which returns EACCES for a privileged port as a non-root user).
final class NginxConfigWriterTests: XCTestCase {
    private let writer = NginxConfigWriter()
    private let paths = AppSupportPaths(root: URL(fileURLWithPath: "/tmp/ktstack-test"))

    func testVhostListensOnWildcardNotLoopback() {
        let vhost = writer.vhost(
            domain: "demo.test",
            root: URL(fileURLWithPath: "/Users/me/Sites/WWW/demo/public"),
            phpFpmSocket: paths.phpFpmSocket("demo"))

        XCTAssertTrue(vhost.contains("listen 0.0.0.0:80;"),
                      "vhost must bind the wildcard privileged port")
        XCTAssertFalse(vhost.contains("127.0.0.1"),
                       "vhost must never bind a specific loopback interface (EACCES without root)")
    }

    func testCustomPortStillWildcard() {
        let vhost = writer.vhost(
            domain: "demo.test",
            root: URL(fileURLWithPath: "/tmp/site"),
            phpFpmSocket: paths.phpFpmSocket("demo"),
            port: 8080)
        XCTAssertTrue(vhost.contains("listen 0.0.0.0:8080;"))
        XCTAssertFalse(vhost.contains("127.0.0.1"))
    }

    func testListenAddressConstantIsWildcard() {
        XCTAssertEqual(NginxConfigWriter.listenAddress, "0.0.0.0")
    }

    func testVhostWiresFastcgiToPoolSocket() {
        let socket = paths.phpFpmSocket("demo")
        let vhost = writer.vhost(domain: "demo.test",
                                 root: URL(fileURLWithPath: "/tmp/site"),
                                 phpFpmSocket: socket)
        XCTAssertTrue(vhost.contains("fastcgi_pass \"unix:\(socket.path)\";"))
        XCTAssertTrue(vhost.contains("server_name demo.test;"))
    }

    func testNodeProxyVhostProxiesToLoopbackPort() {
        let vhost = writer.vhostNodeProxy(domain: "app.test", nodePort: 3001)
        XCTAssertTrue(vhost.contains("listen 0.0.0.0:80;"))
        XCTAssertTrue(vhost.contains("server_name app.test;"))
        XCTAssertTrue(vhost.contains("proxy_pass http://127.0.0.1:3001;"))
        XCTAssertTrue(vhost.contains("proxy_http_version 1.1;"))
        XCTAssertTrue(vhost.contains("proxy_set_header Upgrade $http_upgrade;"))
        XCTAssertTrue(vhost.contains("proxy_set_header Connection \"upgrade\";"))
        XCTAssertFalse(vhost.contains("try_files"))
        XCTAssertFalse(vhost.contains("fastcgi_pass"))
    }

    func testNodeProxyVhostHonoursCustomPort() {
        let vhost = writer.vhostNodeProxy(domain: "app.test", nodePort: 3500, port: 8080)
        XCTAssertTrue(vhost.contains("listen 0.0.0.0:8080;"))
        XCTAssertTrue(vhost.contains("proxy_pass http://127.0.0.1:3500;"))
    }

    func testDomainAndPathValidationRejectInjection() {
        XCTAssertTrue(NginxConfigWriter.isValidDomain("demo.test"))
        XCTAssertFalse(NginxConfigWriter.isValidDomain("demo.test;\n} server {"))
        XCTAssertFalse(NginxConfigWriter.isValidDomain("a b"))
        XCTAssertTrue(NginxConfigWriter.isSafePath("/Users/me/Sites/demo/public"))
        XCTAssertFalse(NginxConfigWriter.isSafePath("/tmp/x;\nroot /etc"))
    }

    func testWriteDemoThrowsOnBadDomain() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ktstack-\(UUID())")
        let p = AppSupportPaths(root: tmp)
        try? p.ensureDirectoryTree()
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertThrowsError(try writer.writeDemo(
            paths: p, domain: "bad;domain", siteRoot: URL(fileURLWithPath: "/tmp/site"), poolName: "demo"))
    }

    func testMasterConfigIncludesSitesEnabled() {
        let conf = writer.masterConfig(paths: paths)
        XCTAssertTrue(conf.contains("include \"\(paths.sitesEnabled.path)/*.conf\";"))
        XCTAssertTrue(conf.contains("error_log \"\(paths.nginxErrorLog.path)\""))
    }

    /// Regression: the real app-support tree lives under "Application Support" (a space), so every
    /// emitted path MUST be double-quoted or nginx errors "invalid number of arguments in pid".
    func testPathsWithSpacesAreQuoted() {
        let spaced = AppSupportPaths(root: URL(fileURLWithPath: "/tmp/with space/KTStack"))
        let conf = writer.masterConfig(paths: spaced)
        XCTAssertTrue(conf.contains("pid \"\(spaced.nginxPid.path)\";"))
        XCTAssertTrue(conf.contains("access_log \"\(spaced.nginxAccessLog.path)\";"))
        let vhost = writer.vhost(domain: "demo.test",
                                 root: URL(fileURLWithPath: "/tmp/with space/site"),
                                 phpFpmSocket: spaced.phpFpmSocket("8.4"))
        XCTAssertTrue(vhost.contains("root \"/tmp/with space/site\";"))
        XCTAssertTrue(vhost.contains("fastcgi_pass \"unix:\(spaced.phpFpmSocket("8.4").path)\";"))
    }
}
