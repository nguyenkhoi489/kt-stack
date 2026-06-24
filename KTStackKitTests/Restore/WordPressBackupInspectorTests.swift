import XCTest
@testable import KTStackKit

final class WordPressBackupInspectorTests: XCTestCase {
    private let inspector = WordPressBackupInspector()

    func testClassifiesWpress() throws {
        let file = try RestoreFixtureBuilder.makeTempDir("insp-wpress")
            .appendingPathComponent("site.wpress")
        try Data("x".utf8).write(to: file)
        XCTAssertEqual(try inspector.inspect(file), .aioWpress)
    }

    func testClassifiesDuplicatorZip() throws {
        let dir = try RestoreFixtureBuilder.makeTempDir("insp-dup")
        let zip = dir.appendingPathComponent("d.zip")
        try RestoreFixtureBuilder.makeDuplicatorZip(to: zip, layout: [
            "dup-installer/dup-database__x.sql": "CREATE TABLE `wp_options` (id int);",
            "wp-load.php": "<?php",
        ])
        try Data("<?php".utf8).write(to: dir.appendingPathComponent("installer.php"))
        XCTAssertEqual(try inspector.inspect(zip), .duplicatorZip)
    }

    func testRejectsZipWithoutSiblingInstaller() throws {
        let zip = try RestoreFixtureBuilder.makeTempDir("insp-noinst").appendingPathComponent("d.zip")
        try RestoreFixtureBuilder.makeDuplicatorZip(to: zip, layout: [
            "dup-installer/dup-database__x.sql": "x",
            "wp-load.php": "<?php",
        ])
        XCTAssertThrowsError(try inspector.inspect(zip)) { error in
            XCTAssertEqual(error as? RestoreArchiveError, .missingDuplicatorInstaller)
        }
    }

    func testRejectsNonWordPressZip() throws {
        let dir = try RestoreFixtureBuilder.makeTempDir("insp-plain")
        let zip = dir.appendingPathComponent("p.zip")
        try RestoreFixtureBuilder.makeDuplicatorZip(to: zip, layout: [
            "readme.txt": "hello",
            "notes/data.csv": "a,b",
        ])
        try Data("<?php".utf8).write(to: dir.appendingPathComponent("installer.php"))
        XCTAssertThrowsError(try inspector.inspect(zip)) { error in
            XCTAssertEqual(error as? RestoreArchiveError, .notWordPressBackup)
        }
    }

    func testRejectsUnsupportedExtension() throws {
        let file = try RestoreFixtureBuilder.makeTempDir("insp-daf")
            .appendingPathComponent("pro.daf")
        try Data("x".utf8).write(to: file)
        XCTAssertThrowsError(try inspector.inspect(file)) { error in
            XCTAssertEqual(error as? RestoreArchiveError, .unsupportedFormat("daf"))
        }
    }
}
