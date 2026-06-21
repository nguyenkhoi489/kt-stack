import XCTest
@testable import KTStackKit

final class ProjectVersionResolverTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-resolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testValidationAndMajorMinor() {
        XCTAssertTrue(ProjectVersionResolver.isValidVersion("8.4"))
        XCTAssertTrue(ProjectVersionResolver.isValidVersion("22.22.3"))
        XCTAssertFalse(ProjectVersionResolver.isValidVersion("8.4; rm -rf /"))
        XCTAssertFalse(ProjectVersionResolver.isValidVersion("../../x"))
        XCTAssertFalse(ProjectVersionResolver.isValidVersion("22.22.3.1"))
        XCTAssertEqual(ProjectVersionResolver.majorMinor(fromConstraint: "^8.3"), "8.3")
        XCTAssertEqual(ProjectVersionResolver.majorMinor(fromConstraint: "8.1.99"), "8.1")
        XCTAssertNil(ProjectVersionResolver.majorMinor(fromConstraint: "nonsense"))
    }

    func testSelectVersionPicksInstalledNodeSemver() {
        let resolver = ProjectVersionResolver()
        let proj = tmp.appendingPathComponent("vongquay")
        try? FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        XCTAssertEqual(resolver.selectVersion(.node, forProjectAt: proj, installed: ["22.22.3"]), "22.22.3")
    }

    func testWalkUpFindsAncestorMarker() throws {
        let proj = tmp.appendingPathComponent("proj")
        let deep = proj.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try "8.1\n".write(to: proj.appendingPathComponent(".php-version"), atomically: true, encoding: .utf8)

        let resolver = ProjectVersionResolver(homeOverride: tmp)
        XCTAssertEqual(resolver.resolve(.php, forProjectAt: deep), "8.1")
    }

    func testComposerPlatformAndRequireParsed() throws {
        let proj = tmp.appendingPathComponent("laravel")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        let json = #"{"config":{"platform":{"php":"8.3.9"}},"require":{"php":"^8.1"}}"#
        try json.write(to: proj.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)

        let resolver = ProjectVersionResolver(homeOverride: tmp)
        XCTAssertEqual(resolver.resolve(.php, forProjectAt: proj), "8.3")
    }

    func testMaliciousMarkerRejectedNoFallbackVersion() throws {
        let proj = tmp.appendingPathComponent("evil")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        try "8.4; rm -rf /\n".write(to: proj.appendingPathComponent(".php-version"),
                                    atomically: true, encoding: .utf8)

        let resolver = ProjectVersionResolver(homeOverride: tmp)
        XCTAssertNil(resolver.resolve(.php, forProjectAt: proj, walkUp: false))
    }

    func testHighestUsesNumericNotLexicographicOrder() {
        XCTAssertEqual(ProjectVersionResolver.highest(["8.1", "8.10", "8.2", "8.9"]), "8.10")
        XCTAssertEqual(ProjectVersionResolver.highest(["8.1", "8.3", "8.4"]), "8.4")
        XCTAssertNil(ProjectVersionResolver.highest(["../../bin", "8.4; rm"]))
    }

    func testSelectVersionUnifiesMarkerPreferredFallback() throws {
        let proj = tmp.appendingPathComponent("noMarker")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        let resolver = ProjectVersionResolver(homeOverride: tmp)
        let installed = ["8.1", "8.3", "8.4"]

        XCTAssertEqual(resolver.selectVersion(.php, forProjectAt: proj, installed: installed, preferred: "8.3"), "8.3")
        XCTAssertEqual(resolver.selectVersion(.php, forProjectAt: proj, installed: installed, preferred: "9.9"), "8.4")
        XCTAssertEqual(resolver.selectVersion(.php, forProjectAt: proj, installed: installed, preferred: nil), "8.4")
    }

    func testSelectVersionIgnoresMaliciousInstalledDirNames() throws {
        let proj = tmp.appendingPathComponent("clean")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        let resolver = ProjectVersionResolver(homeOverride: tmp)
        XCTAssertEqual(resolver.selectVersion(.php, forProjectAt: proj, installed: ["8.4", "../../bin"]), "8.4")
    }

    func testConfinedBinaryRejectsInvalidVersionString() throws {
        let paths = AppSupportPaths(root: tmp.appendingPathComponent("as"))
        XCTAssertThrowsError(try ShellRuntimeBinResolver(paths: paths).confinedBinary(.php, version: "../../bin"))
    }

    func testConfinedBinaryStaysInRuntimeRoot() throws {
        let root = tmp.appendingPathComponent("appsupport")
        let paths = AppSupportPaths(root: root)
        let binDir = paths.runtimeBin("php", "8.4")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let php = binDir.appendingPathComponent("php")
        try "#!/bin/sh\n".write(to: php, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: php.path)

        let resolver = ShellRuntimeBinResolver(paths: paths)
        let resolved = try resolver.confinedBinary(.php, version: "8.4")
        XCTAssertTrue(resolved.path.hasPrefix(paths.runtimes.standardizedFileURL.path + "/"))
        XCTAssertThrowsError(try resolver.confinedBinary(.php, version: "9.9"))
    }
}
