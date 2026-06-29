import Darwin
import XCTest
@testable import KTStackKit

final class NodeSiteControllerSpecTests: XCTestCase {
    private let controller = NodeSiteController()

    private func site(port: Int?) -> Site {
        Site(
            name: "app",
            path: "/Users/me/Sites/app",
            docroot: "/Users/me/Sites/app",
            domain: "app.test",
            phpVersion: "8.4",
            type: .node,
            nodePort: port,
            nodeCommand: nil,
            nodeEnabled: false
        )
    }

    func testProbeStoppedWhenNoPort() async {
        let state = await controller.probe(site(port: nil))
        XCTAssertEqual(state, .stopped)
    }

    func testProbeStoppedWhenNothingListens() async {
        let state = await controller.probe(site(port: 59_999))
        XCTAssertEqual(state, .stopped)
    }

    func testProbeRunningWhenListenerAnswers() async throws {
        let (fd, port) = try Self.openListener()
        defer { close(fd) }
        let state = await controller.probe(site(port: port))
        XCTAssertEqual(state, .running)
    }

    func testBadgeAndServiceStatusMapping() {
        XCTAssertEqual(NodeSiteController.State.running.badgeLabel, "Running")
        XCTAssertEqual(NodeSiteController.State.stopped.badgeLabel, "Stopped")
        XCTAssertTrue(NodeSiteController.State.running.isHealthy)
        XCTAssertFalse(NodeSiteController.State.stopped.isHealthy)
        XCTAssertEqual(NodeSiteController.State.running.serviceStatus, .running)
        XCTAssertEqual(NodeSiteController.State.stopped.serviceStatus, .stopped)
    }

    private static func openListener() throws -> (Int32, Int) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw error("socket") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 1) == 0 else { close(fd); throw error("bind/listen") }
        var named = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &named) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard got == 0 else { close(fd); throw error("getsockname") }
        return (fd, Int(UInt16(bigEndian: named.sin_port)))
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "NodeSiteControllerSpecTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
