import XCTest
@testable import KTStackKit

final class SiteInspectorNodeScriptsTests: XCTestCase {
    private let inspector = SiteInspector()
    private let fm = FileManager.default

    private func makeFolder(packageJSON: String?) throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-node-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let packageJSON {
            try packageJSON.write(to: folder.appendingPathComponent("package.json"),
                                  atomically: true, encoding: .utf8)
        }
        return folder
    }

    func testPrefersStartScript() throws {
        let folder = try makeFolder(packageJSON: #"{"scripts": {"start": "node server.js", "dev": "vite"}}"#)
        defer { try? fm.removeItem(at: folder) }
        XCTAssertEqual(inspector.suggestedNodeCommand(at: folder), "npm run start")
    }

    func testFallsBackToDevScript() throws {
        let folder = try makeFolder(packageJSON: #"{"scripts": {"dev": "vite"}}"#)
        defer { try? fm.removeItem(at: folder) }
        XCTAssertEqual(inspector.suggestedNodeCommand(at: folder), "npm run dev")
    }

    func testReturnsNilWhenNoUsableScript() throws {
        let folder = try makeFolder(packageJSON: #"{"scripts": {"build": "tsc"}}"#)
        defer { try? fm.removeItem(at: folder) }
        XCTAssertNil(inspector.suggestedNodeCommand(at: folder))
    }

    func testReturnsNilForMalformedJSON() throws {
        let folder = try makeFolder(packageJSON: "{ not json")
        defer { try? fm.removeItem(at: folder) }
        XCTAssertNil(inspector.suggestedNodeCommand(at: folder))
    }

    func testReturnsNilWhenPackageJSONMissing() throws {
        let folder = try makeFolder(packageJSON: nil)
        defer { try? fm.removeItem(at: folder) }
        XCTAssertNil(inspector.suggestedNodeCommand(at: folder))
    }
}
