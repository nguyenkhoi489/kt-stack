import XCTest
@testable import KTStackKit

/// Unit tests for the runtime-management layer: marker-file resolution, the download manifest +
/// installed scan, version clamping, and checksum verification. Live download/extract is exercised
/// manually (network) — these cover the pure logic.
final class RuntimeManagementTests: XCTestCase {
    func testParseKTStackRCTolerantKeyValue() {
        let rc = """
        # project runtimes
        php = "8.3"
        node=22
        python = '3.12'
        bogus
        """
        let map = VersionResolver.parseKTStackRC(rc)
        XCTAssertEqual(map["php"], "8.3")
        XCTAssertEqual(map["node"], "22")
        XCTAssertEqual(map["python"], "3.12")
        XCTAssertNil(map["bogus"])
    }

    func testVersionResolverPrecedenceAndFallbacks() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try ".ktstackrc has php only\nphp = \"8.1\"".write(to: dir.appendingPathComponent(".ktstackrc"), atomically: true, encoding: .utf8)
        try "v22.5.0".write(to: dir.appendingPathComponent(".nvmrc"), atomically: true, encoding: .utf8) // leading v stripped

        let r = VersionResolver()
        let v = r.versions(forProjectAt: dir)
        XCTAssertEqual(v[.php], "8.1") // from .ktstackrc
        XCTAssertEqual(v[.node], "22.5.0") // .nvmrc fallback, v-stripped
    }

    func testKTStackRCBeatsLanguageFallback() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "php = \"8.4\"".write(to: dir.appendingPathComponent(".ktstackrc"), atomically: true, encoding: .utf8)
        try "7.4".write(to: dir.appendingPathComponent(".php-version"), atomically: true, encoding: .utf8)
        XCTAssertEqual(VersionResolver().version(.php, forProjectAt: dir), "8.4")
    }

    func testInstalledScanAndAvailableExcludesInstalled() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppSupportPaths(root: root)
        // Install Node 22.22.3 (the manifest version) by creating its marker binary.
        let nodeBin = paths.runtimeBin("node", "22.22.3")
        try FileManager.default.createDirectory(at: nodeBin, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: nodeBin.appendingPathComponent("node").path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )

        let catalog = RuntimeCatalog(paths: paths)
        XCTAssertEqual(catalog.installedVersions(.node), ["22.22.3"])
        XCTAssertTrue(catalog.isInstalled(.node, "22.22.3"))
        // The installed version is filtered out of the available list.
        XCTAssertFalse(catalog.availableReleases(.node).contains { $0.version == "22.22.3" })
        // PHP still available (not installed).
        XCTAssertTrue(catalog.availableReleases(.php).contains { $0.version == "8.4" })
    }

    func testManifestEntriesAreWellFormed() {
        XCTAssertFalse(RuntimeCatalog.manifest.isEmpty)
        for r in RuntimeCatalog.manifest {
            XCTAssertEqual(r.url.scheme, "https")
            XCTAssertEqual(r.sha256.count, 64, "\(r.id) sha256 must be 64 hex chars")
        }
    }

    func testPHPManifestEntryHostedOnReleasesWithArchFilename() {
        let php = RuntimeCatalog.manifest.filter { $0.language == .php }
        XCTAssertFalse(php.isEmpty, "PHP must have at least one downloadable version")
        // Nothing is bundled — the default 8.4 is itself a download entry.
        XCTAssertTrue(php.contains { $0.version == "8.4" }, "default PHP 8.4 must be downloadable")
        for r in php {
            XCTAssertEqual(r.url.host, "github.com")
            XCTAssertTrue(r.url.path.contains("/releases/download/"), "\(r.id) must resolve to a release asset")
            XCTAssertEqual(
                r.url.lastPathComponent,
                "php-\(r.version)-arm64.tar.gz",
                "filename must follow <name>-<version>-<arch>.tar.gz"
            )
        }
    }

    func testServiceBinaryReleaseURLResolvesUnderReleasesHost() {
        let redis = ServiceBinaryCatalog.manifest.first { $0.kind == .redis }
        XCTAssertNotNil(redis)
        XCTAssertEqual(redis?.url.host, "github.com")
        XCTAssertTrue(redis?.url.path.contains("/releases/download/") ?? false)
        XCTAssertEqual(redis?.url.lastPathComponent, "redis-\(redis!.version)-\(ServiceBinaryCatalog.arch).tar.gz")
    }

    func testResolvedPHPClampsUninstalledPinToInstalled() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppSupportPaths(root: root)
        // Only 8.4 installed.
        let bin = paths.runtimeBin("php", "8.4")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: bin.appendingPathComponent("php-fpm").path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )

        // Project pins 8.1 (NOT installed) → clamp to the installed 8.4.
        let project = try tempDir()
        defer { try? FileManager.default.removeItem(at: project) }
        try "php = \"8.1\"".write(to: project.appendingPathComponent(".ktstackrc"), atomically: true, encoding: .utf8)

        let switcher = VersionSwitcher(paths: paths)
        XCTAssertEqual(switcher.resolvedPHPVersion(projectDir: project, globalDefault: "8.4"), "8.4")
    }

    func testChecksumVerifyPassesAndRejects() throws {
        let file = try tempDir().appendingPathComponent("blob.bin")
        try Data("ktstack-runtime".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let digest = try ChecksumVerifier.sha256(of: file)
        XCTAssertEqual(digest.count, 64)
        XCTAssertNoThrow(try ChecksumVerifier.verify(file, expected: digest.uppercased())) // case-insensitive
        XCTAssertThrowsError(try ChecksumVerifier.verify(file, expected: String(repeating: "0", count: 64)))
    }

    func testPHPModulesParseStripsHeadersDeDupesAndSorts() {
        let output = """
        [PHP Modules]
        curl
        Core
        gd

        [Zend Modules]
        Zend OPcache
        curl
        """
        // Headers ([...]) and blanks dropped; lowercased, de-duped, sorted.
        XCTAssertEqual(PHPModules.parse(output), ["core", "curl", "gd", "zend opcache"])
    }

    func testPHPModulesParseEmptyOutput() {
        XCTAssertEqual(PHPModules.parse(""), [])
    }

    func testPHPModulesListEmptyWhenBinaryAbsent() throws {
        let paths = try AppSupportPaths(root: tempDir())
        XCTAssertEqual(PHPModules.list(version: "9.9", paths: paths), [])
    }

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-rt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
