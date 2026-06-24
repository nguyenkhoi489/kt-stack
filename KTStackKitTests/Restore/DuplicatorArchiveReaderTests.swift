import XCTest
@testable import KTStackKit

final class DuplicatorArchiveReaderTests: XCTestCase {
    private var staging: URL!

    override func setUpWithError() throws {
        staging = try RestoreFixtureBuilder.makeTempDir("dup-staging")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: staging)
    }

    func testLocatesDumpAndDerivesPrefixFromRealisticLayout() async throws {
        let zip = try RestoreFixtureBuilder.makeTempDir("dup-zip").appendingPathComponent("backup.zip")
        let dump = """
        CREATE TABLE `mt_options` (id int);
        INSERT INTO `mt_options` VALUES (1,'siteurl','https://old.test','yes');
        """
        try RestoreFixtureBuilder.makeDuplicatorZip(to: zip, layout: [
            "20260615_site_hash_installer-backup.php": "<?php // duplicator installer",
            "wp-load.php": "<?php // wp",
            "wp-includes/version.php": "<?php $wp_version='6.4';",
            "dup-installer/dup-database__abcdef.sql": dump,
        ])

        let payload = try await DuplicatorArchiveReader().extract(zip, into: staging) { _ in }

        XCTAssertFalse(payload.isContentOnly)
        XCTAssertEqual(payload.kind, .duplicatorZip)
        XCTAssertEqual(payload.tablePrefix, "mt_")
        XCTAssertEqual(payload.sourceURL, "https://old.test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: payload.sqlDump.path))
    }

    func testStripsInstallerBackupAndDupInstallerFromDocroot() async throws {
        let zip = try RestoreFixtureBuilder.makeTempDir("dup-zip2").appendingPathComponent("backup.zip")
        try RestoreFixtureBuilder.makeDuplicatorZip(to: zip, layout: [
            "20260615_site_hash_installer-backup.php": "<?php",
            "wp-load.php": "<?php",
            "dup-installer/dup-database__abcdef.sql": "CREATE TABLE `wp_options` (id int);",
        ])

        let payload = try await DuplicatorArchiveReader().extract(zip, into: staging) { _ in }

        XCTAssertFalse(FileManager.default.fileExists(atPath: payload.docroot.appendingPathComponent("20260615_site_hash_installer-backup.php").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: payload.docroot.appendingPathComponent("dup-installer").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payload.docroot.appendingPathComponent("wp-load.php").path))
        XCTAssertEqual(payload.tablePrefix, "wp_")
    }
}
