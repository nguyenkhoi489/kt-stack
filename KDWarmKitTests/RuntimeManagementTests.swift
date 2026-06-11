import XCTest
@testable import KDWarmKit

/// Unit tests for the runtime-management layer: marker-file resolution, the download manifest +
/// installed scan, version clamping, and checksum verification. Live download/extract is exercised
/// manually (network) — these cover the pure logic.
final class RuntimeManagementTests: XCTestCase {

    // MARK: - VersionResolver

    func testParseKDWarmRCTolerantKeyValue() {
        let rc = """
        # project runtimes
        php = "8.3"
        node=22
        python = '3.12'
        bogus
        """
        let map = VersionResolver.parseKDWarmRC(rc)
        XCTAssertEqual(map["php"], "8.3")
        XCTAssertEqual(map["node"], "22")
        XCTAssertEqual(map["python"], "3.12")
        XCTAssertNil(map["bogus"])
    }

    func testVersionResolverPrecedenceAndFallbacks() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try ".kdwarmrc has php only\nphp = \"8.1\"".write(to: dir.appendingPathComponent(".kdwarmrc"), atomically: true, encoding: .utf8)
        try "v22.5.0".write(to: dir.appendingPathComponent(".nvmrc"), atomically: true, encoding: .utf8)   // leading v stripped
        try "3.11.9".write(to: dir.appendingPathComponent(".python-version"), atomically: true, encoding: .utf8)

        let r = VersionResolver()
        let v = r.versions(forProjectAt: dir)
        XCTAssertEqual(v[.php], "8.1")        // from .kdwarmrc
        XCTAssertEqual(v[.node], "22.5.0")    // .nvmrc fallback, v-stripped
        XCTAssertEqual(v[.python], "3.11.9")  // .python-version fallback
    }

    func testKDWarmRCBeatsLanguageFallback() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "php = \"8.4\"".write(to: dir.appendingPathComponent(".kdwarmrc"), atomically: true, encoding: .utf8)
        try "7.4".write(to: dir.appendingPathComponent(".php-version"), atomically: true, encoding: .utf8)
        XCTAssertEqual(VersionResolver().version(.php, forProjectAt: dir), "8.4")
    }

    // MARK: - RuntimeCatalog

    func testInstalledScanAndAvailableExcludesInstalled() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppSupportPaths(root: root)
        // Install Go 1.26.4 (the manifest version) by creating its marker binary.
        let goBin = paths.runtimeBin("go", "1.26.4")
        try FileManager.default.createDirectory(at: goBin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: goBin.appendingPathComponent("go").path,
                                       contents: Data(), attributes: [.posixPermissions: 0o755])

        let catalog = RuntimeCatalog(paths: paths)
        XCTAssertEqual(catalog.installedVersions(.go), ["1.26.4"])
        XCTAssertTrue(catalog.isInstalled(.go, "1.26.4"))
        // The installed version is filtered out of the available list.
        XCTAssertFalse(catalog.availableReleases(.go).contains { $0.version == "1.26.4" })
        // Node still available (not installed).
        XCTAssertTrue(catalog.availableReleases(.node).contains { $0.version == "22.22.3" })
    }

    func testManifestEntriesAreWellFormed() {
        XCTAssertFalse(RuntimeCatalog.manifest.isEmpty)
        for r in RuntimeCatalog.manifest {
            XCTAssertEqual(r.url.scheme, "https")
            XCTAssertEqual(r.sha256.count, 64, "\(r.id) sha256 must be 64 hex chars")
        }
    }

    // MARK: - VersionSwitcher clamping

    func testResolvedPHPClampsUninstalledPinToInstalled() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppSupportPaths(root: root)
        // Only 8.4 installed.
        let bin = paths.runtimeBin("php", "8.4")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bin.appendingPathComponent("php-fpm").path,
                                       contents: Data(), attributes: [.posixPermissions: 0o755])

        // Project pins 8.1 (NOT installed) → clamp to the installed 8.4.
        let project = try tempDir()
        defer { try? FileManager.default.removeItem(at: project) }
        try "php = \"8.1\"".write(to: project.appendingPathComponent(".kdwarmrc"), atomically: true, encoding: .utf8)

        let switcher = VersionSwitcher(paths: paths)
        XCTAssertEqual(switcher.resolvedPHPVersion(projectDir: project, globalDefault: "8.4"), "8.4")
    }

    // MARK: - ChecksumVerifier

    func testChecksumVerifyPassesAndRejects() throws {
        let file = try tempDir().appendingPathComponent("blob.bin")
        try Data("kdwarm-runtime".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let digest = try ChecksumVerifier.sha256(of: file)
        XCTAssertEqual(digest.count, 64)
        XCTAssertNoThrow(try ChecksumVerifier.verify(file, expected: digest.uppercased()))  // case-insensitive
        XCTAssertThrowsError(try ChecksumVerifier.verify(file, expected: String(repeating: "0", count: 64)))
    }

    // MARK: - Helpers

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-rt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
