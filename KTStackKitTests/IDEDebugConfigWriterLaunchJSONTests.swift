import XCTest
@testable import KTStackKit

final class IDEDebugConfigWriterLaunchJSONTests: XCTestCase {
    func testLaunchJSONStaysValidForTrickyDocroots() throws {
        let docroots = [
            "",
            "/",
            "/Users/x/Sites/site",
            "/Users/x/Sites/with space/public",
            "/Users/x/Sites/quote\"name/public",
            "/Users/x/Sites/emoji-🚀/public",
            "/Users/x/Sites/line\nbreak/public",
            "/Users/x/Sites/tab\tchar/public",
            "/Users/x/Sites/back\\slash/public",
        ]
        for docroot in docroots {
            let json = IDEDebugConfigWriter.launchJSON(docroot: docroot)
            XCTAssertFalse(json.isEmpty, "empty output for \(docroot.debugDescription)")

            let data = try XCTUnwrap(json.data(using: .utf8))
            let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(parsed["version"] as? String, "0.2.0")

            let config = try XCTUnwrap((parsed["configurations"] as? [[String: Any]])?.first)
            let mappings = try XCTUnwrap(config["pathMappings"] as? [String: String])
            XCTAssertEqual(
                mappings[docroot],
                "${workspaceFolder}",
                "missing mapping for \(docroot.debugDescription)"
            )
        }
    }

    func testLaunchJSONHasTrailingNewline() {
        XCTAssertTrue(IDEDebugConfigWriter.launchJSON(docroot: "/Users/x/Sites/demo").hasSuffix("\n"))
    }

    func testLaunchJSONHonorsCustomPort() throws {
        let json = IDEDebugConfigWriter.launchJSON(docroot: "/Users/x/Sites/demo", port: 9100)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let config = try XCTUnwrap((parsed["configurations"] as? [[String: Any]])?.first)
        XCTAssertEqual(config["port"] as? Int, 9100)
    }
}
