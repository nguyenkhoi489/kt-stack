import XCTest
@testable import KTStackKit

final class SiteBackendSupervisorTests: XCTestCase {
    private func site(_ domain: String, type: SiteType, backendPort: Int?) -> Site {
        Site(name: domain, path: "/s", docroot: "/s", domain: domain, phpVersion: "8.4", type: type, backendPort: backendPort)
    }

    func testManagedKeepsOnlyPHPSitesWithABackendPort() {
        let sites = [
            site("a.test", type: .php, backendPort: 4001),
            site("b.test", type: .php, backendPort: nil), // not yet backfilled → excluded
            site("c.test", type: .staticSite, backendPort: nil),
            site("d.test", type: .node, backendPort: nil),
        ]
        XCTAssertEqual(SiteBackendSupervisor.managed(sites).map(\.domain), ["a.test"])
    }

    func testBackendPathsAreScopedPerSiteID() {
        let paths = AppSupportPaths(root: URL(fileURLWithPath: "/tmp/ktstack-test"))
        XCTAssertEqual(paths.siteBackendLabel("ABC"), "com.ktstack.site.ABC")
        XCTAssertTrue(paths.siteBackendLabel("ABC").hasPrefix(SiteBackendSupervisor.labelPrefix))
        XCTAssertTrue(paths.siteBackendConf("ABC").path.hasSuffix("nginx/backends/ABC.conf"))
        XCTAssertTrue(paths.siteBackendPid("ABC").path.hasSuffix("run/site-ABC.pid"))
    }
}
