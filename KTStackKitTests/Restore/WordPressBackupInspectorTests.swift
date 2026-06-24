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
        let zip = try RestoreFixtureBuilder.makeTempDir("insp-dup").appendingPathComponent("d.zip")
        try RestoreFixtureBuilder.makeDuplicatorZip(to: zip, layout: [
            "installer.php": "<?php",
            "wp-load.php": "<?php",
            "database.sql": "x",
        ])
        XCTAssertEqual(try inspector.inspect(zip), .duplicatorZip)
    }

    func testRejectsNonWordPressZip() throws {
        let zip = try RestoreFixtureBuilder.makeTempDir("insp-plain").appendingPathComponent("p.zip")
        try RestoreFixtureBuilder.makeDuplicatorZip(to: zip, layout: [
            "readme.txt": "hello",
            "notes/data.csv": "a,b",
        ])
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
