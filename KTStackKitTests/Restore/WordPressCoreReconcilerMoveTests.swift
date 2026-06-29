import XCTest
@testable import KTStackKit

final class WordPressCoreReconcilerMoveTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try RestoreFixtureBuilder.makeTempDir("reconcile-root")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFullSiteMovesTreeIntoDocroot() async throws {
        let fm = FileManager.default
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        let source = staging.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: source.appendingPathComponent("wp-content/themes/x"), withIntermediateDirectories: true)
        try Data("<?php".utf8).write(to: source.appendingPathComponent("wp-load.php"))
        try Data("body{}".utf8).write(to: source.appendingPathComponent("wp-content/themes/x/style.css"))

        let payload = PreparedWordPressPayload(
            stagingRoot: staging,
            docroot: source,
            sqlDump: staging.appendingPathComponent("database.sql"),
            tablePrefix: "wp_",
            sourceURL: "https://old.test",
            wpVersion: nil,
            isContentOnly: false,
            kind: .duplicatorZip
        )

        let target = root.appendingPathComponent("sites/site", isDirectory: true)
        let reconciler = WordPressCoreReconciler(
            php: URL(fileURLWithPath: "/usr/bin/true"), phpIni: nil,
            wpCliPhar: URL(fileURLWithPath: "/dev/null")
        )
        let result = try await reconciler.reconcile(payload: payload, targetDocroot: target) { _ in }

        XCTAssertNil(result.coreVersion)
        XCTAssertFalse(result.usedLatestFallback)
        XCTAssertTrue(fm.fileExists(atPath: target.appendingPathComponent("wp-load.php").path))
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("wp-content/themes/x/style.css")), "body{}")
    }
}
