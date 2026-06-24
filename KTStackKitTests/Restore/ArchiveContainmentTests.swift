import XCTest
@testable import KTStackKit

final class ArchiveContainmentTests: XCTestCase {
    func testSafeResolveAcceptsNestedPath() throws {
        let base = try RestoreFixtureBuilder.makeTempDir("safe-ok")
        let resolved = try RestoreContainment.safeResolve(base: base, entryPath: "wp-content/themes/x/style.css")
        XCTAssertTrue(resolved.path.hasPrefix(base.standardizedFileURL.path + "/"))
    }

    func testSafeResolveRejectsTraversal() throws {
        let base = try RestoreFixtureBuilder.makeTempDir("safe-trav")
        XCTAssertThrowsError(try RestoreContainment.safeResolve(base: base, entryPath: "../escape"))
    }

    func testSafeResolveRejectsAbsolutePath() throws {
        let base = try RestoreFixtureBuilder.makeTempDir("safe-abs")
        XCTAssertThrowsError(try RestoreContainment.safeResolve(base: base, entryPath: "/etc/passwd"))
    }

    func testSymlinkInsideTreeIsRejected() throws {
        let base = try RestoreFixtureBuilder.makeTempDir("safe-link")
        let link = base.appendingPathComponent("evil-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        XCTAssertThrowsError(try RestoreContainment.assertNoSymlinksOrEscapes(in: base)) { error in
            guard let restoreError = error as? RestoreArchiveError,
                  case .symlinkRejected = restoreError else {
                return XCTFail("expected symlinkRejected, got \(error)")
            }
        }
    }

    func testCleanTreePasses() throws {
        let base = try RestoreFixtureBuilder.makeTempDir("safe-clean")
        let file = base.appendingPathComponent("a/b.txt")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: file)
        XCTAssertNoThrow(try RestoreContainment.assertNoSymlinksOrEscapes(in: base))
    }
}
