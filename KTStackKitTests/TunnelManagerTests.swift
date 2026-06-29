import XCTest
@testable import KTStackKit

@MainActor
final class TunnelManagerTests: XCTestCase {
    private func tempManager() -> (TunnelManager, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-tunnel-mgr-\(UUID().uuidString)")
        return (TunnelManager(paths: AppSupportPaths(root: root)), root)
    }

    private func site(_ domain: String, id: UUID = UUID()) -> Site {
        Site(
            id: id,
            name: domain,
            path: "/tmp",
            docroot: "/tmp",
            domain: domain,
            phpVersion: "8.4",
            type: .staticSite,
            secure: false
        )
    }

    func testInFlightGuardAllowsOneSessionPerSite() {
        let (mgr, root) = tempManager()
        defer { try? FileManager.default.removeItem(at: root) }
        let s = site("demo.test")
        mgr.start(site: s)
        mgr.start(site: s)
        XCTAssertEqual(mgr.sessions.count, 1)
        XCTAssertTrue(mgr.isSharing(s.id))
        if case .starting = mgr.session(s.id)!.status {} else { XCTFail("expected .starting") }
        mgr.stop(site: s.id)
        XCTAssertFalse(mgr.isSharing(s.id))
    }

    func testReconcileStopsRenamedAndRemovedSites() {
        let (mgr, root) = tempManager()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = site("a.test"), b = site("b.test")
        mgr.start(site: a)
        mgr.start(site: b)
        XCTAssertEqual(mgr.sessions.count, 2)

        let renamedA = site("a2.test", id: a.id)
        mgr.reconcile(sites: [renamedA])
        XCTAssertNil(mgr.session(a.id), "domain changed → tunnel stopped")
        XCTAssertNil(mgr.session(b.id), "site removed → tunnel stopped")
    }

    func testReconcileKeepsUnchangedSite() {
        let (mgr, root) = tempManager()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = site("keep.test")
        mgr.start(site: a)
        mgr.reconcile(sites: [a])
        XCTAssertTrue(mgr.isSharing(a.id))
        mgr.stop(site: a.id)
    }

    func testReconcileStopsSecureFlippedSite() {
        let (mgr, root) = tempManager()
        defer { try? FileManager.default.removeItem(at: root) }
        let plain = site("flip.test")
        mgr.start(site: plain)
        var flipped = plain
        flipped.secure = true
        mgr.reconcile(sites: [flipped])
        XCTAssertNil(mgr.session(plain.id), "secure-flip changes origin port → tunnel stopped")
    }

    func testReShareAfterStopCreatesFreshSession() {
        let (mgr, root) = tempManager()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = site("again.test")
        mgr.start(site: a)
        mgr.stop(site: a.id)
        XCTAssertFalse(mgr.isSharing(a.id))
        mgr.start(site: a)
        XCTAssertEqual(mgr.sessions.count, 1)
        XCTAssertTrue(mgr.isSharing(a.id))
        mgr.stop(site: a.id)
    }

    func testReapStaleJobsRemovesTunnelVhostFiles() throws {
        let (mgr, root) = tempManager()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppSupportPaths(root: root)
        try paths.ensureDirectoryTree()
        let stale = paths.vhost("tunnel-\(UUID().uuidString)")
        try "server {}".write(to: stale, atomically: true, encoding: .utf8)

        mgr.reapStaleJobs()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    func testProbeRejectsAnyTestDomainRedirect() {
        let decision = TunnelController.probeDecision(
            statusCode: 302,
            locationHost: "other.test",
            publicHost: "demo.trycloudflare.com",
            localDomain: "app.test"
        )
        guard case let .failed(message) = decision else {
            XCTFail("Expected failed redirect decision, got \(decision)")
            return
        }
        XCTAssertTrue(message.contains("other.test"))
    }
}
