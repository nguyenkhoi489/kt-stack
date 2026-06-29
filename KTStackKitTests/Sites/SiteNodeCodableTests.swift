import XCTest
@testable import KTStackKit

final class SiteNodeCodableTests: XCTestCase {
    func testDecodesLegacySiteWithoutNodeFields() throws {
        let legacy = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "demo",
            "path": "/tmp/demo",
            "docroot": "/tmp/demo/public",
            "domain": "demo.test",
            "phpVersion": "8.4",
            "type": "php",
            "secure": false
        }
        """.data(using: .utf8)!

        let site = try JSONDecoder().decode(Site.self, from: legacy)
        XCTAssertNil(site.nodePort)
        XCTAssertNil(site.nodeCommand)
        XCTAssertFalse(site.nodeEnabled)
        XCTAssertEqual(site.domain, "demo.test")
    }

    func testDecodesLegacySiteWithoutSecureField() throws {
        let legacy = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "name": "old",
            "path": "/tmp/old",
            "docroot": "/tmp/old",
            "domain": "old.test",
            "phpVersion": "8.4",
            "type": "staticSite"
        }
        """.data(using: .utf8)!

        let site = try JSONDecoder().decode(Site.self, from: legacy)
        XCTAssertFalse(site.secure)
        XCTAssertFalse(site.nodeEnabled)
    }

    func testRoundTripPreservesNodeFields() throws {
        let original = Site(
            name: "app",
            path: "/tmp/app",
            docroot: "/tmp/app",
            domain: "app.test",
            phpVersion: "8.4",
            type: .node,
            nodePort: 3001,
            nodeCommand: "npm run dev",
            nodeEnabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Site.self, from: data)
        XCTAssertEqual(decoded.nodePort, 3001)
        XCTAssertEqual(decoded.nodeCommand, "npm run dev")
        XCTAssertTrue(decoded.nodeEnabled)
        XCTAssertEqual(decoded, original)
    }
}
