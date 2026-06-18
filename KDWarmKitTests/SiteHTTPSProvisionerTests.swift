import XCTest
@testable import KDWarmKit

final class SiteHTTPSProvisionerTests: XCTestCase {
    func testEnableHTTPSInstallsCAWhenUntrustedThenMintsLeaf() throws {
        var calls: [String] = []
        let provisioner = SiteHTTPSProvisioner(
            caCert: URL(fileURLWithPath: "/tmp/rootCA.pem"),
            tld: "test",
            trustQuery: { _ in
                calls.append("trust")
                return false
            },
            installCA: {
                calls.append("install")
            },
            mintLeaf: { domain, tld in
                calls.append("mint:\(domain):\(tld)")
            }
        )

        try provisioner.enableHTTPS(for: Site(name: "app",
                                              path: "/tmp/app",
                                              docroot: "/tmp/app/public",
                                              domain: "app.test",
                                              phpVersion: "8.4",
                                              type: .php))

        XCTAssertEqual(calls, ["trust", "install", "mint:app.test:test"])
    }

    func testEnableHTTPSSkipsCAInstallWhenAlreadyTrusted() throws {
        var calls: [String] = []
        let provisioner = SiteHTTPSProvisioner(
            caCert: URL(fileURLWithPath: "/tmp/rootCA.pem"),
            tld: "test",
            trustQuery: { _ in
                calls.append("trust")
                return true
            },
            installCA: {
                calls.append("install")
            },
            mintLeaf: { domain, tld in
                calls.append("mint:\(domain):\(tld)")
            }
        )

        try provisioner.enableHTTPS(for: Site(name: "blog",
                                              path: "/tmp/blog",
                                              docroot: "/tmp/blog/public",
                                              domain: "blog.test",
                                              phpVersion: "8.4",
                                              type: .php))

        XCTAssertEqual(calls, ["trust", "mint:blog.test:test"])
    }
}
