import XCTest
@testable import KTStackKit

final class SiteConfigGeneratorNodeTests: XCTestCase {
    private let fm = FileManager.default

    private func makePaths() -> (AppSupportPaths, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-node-gen-\(UUID().uuidString)", isDirectory: true)
        let paths = AppSupportPaths(root: root)
        try? paths.ensureDirectoryTree()
        return (paths, root)
    }

    private func nodeSite(enabled: Bool, port: Int?) -> Site {
        Site(
            name: "app",
            path: "/tmp/app",
            docroot: "/tmp/app",
            domain: "app.test",
            phpVersion: "8.4",
            type: .node,
            nodePort: port,
            nodeCommand: "npm run dev",
            nodeEnabled: enabled
        )
    }

    func testNodeSiteWithPortEmitsProxyVhost() {
        let (paths, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        let gen = SiteConfigGenerator(paths: paths)
        let vhost = gen.vhostText(for: nodeSite(enabled: true, port: 3001), port: 80)
        XCTAssertTrue(vhost.contains("proxy_pass http://127.0.0.1:3001;"))
        XCTAssertFalse(vhost.contains("try_files"))
    }

    func testNodeSiteWithPortProxiesRegardlessOfEnabledFlag() {
        let (paths, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        let gen = SiteConfigGenerator(paths: paths)
        let vhost = gen.vhostText(for: nodeSite(enabled: false, port: 3001), port: 80)
        XCTAssertTrue(vhost.contains("proxy_pass http://127.0.0.1:3001;"))
        XCTAssertFalse(vhost.contains("try_files"))
    }

    func testNodeSiteWithoutPortStaysStatic() {
        let (paths, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        let gen = SiteConfigGenerator(paths: paths)
        let vhost = gen.vhostText(for: nodeSite(enabled: true, port: nil), port: 80)
        XCTAssertFalse(vhost.contains("proxy_pass"))
        XCTAssertTrue(vhost.contains("try_files $uri $uri/ =404;"))
    }

    func testSecureNodeSiteProxiesOverTLS() throws {
        let (paths, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        let certDir = paths.siteCertDir("app.test")
        try fm.createDirectory(at: certDir, withIntermediateDirectories: true)
        try Data().write(to: paths.siteCert("app.test"))
        try Data().write(to: paths.siteKey("app.test"))

        var site = nodeSite(enabled: true, port: 3001)
        site.secure = true
        let gen = SiteConfigGenerator(paths: paths)
        let vhost = gen.vhostText(for: site, port: 80)
        XCTAssertTrue(vhost.contains("listen 0.0.0.0:443 ssl;"))
        XCTAssertTrue(vhost.contains("proxy_pass http://127.0.0.1:3001;"))
        XCTAssertTrue(vhost.contains("return 301 https://$host$request_uri;"))
        XCTAssertFalse(vhost.contains("fastcgi_pass"))
    }
}
