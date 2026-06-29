import XCTest
@testable import KTStackKit

final class PHPIniStoreTests: XCTestCase {
    private var root: URL!
    private var paths: AppSupportPaths!
    private var store: PHPIniStore!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-ini-\(UUID().uuidString)")
        paths = AppSupportPaths(root: root)
        store = PHPIniStore(paths: paths)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSeedCreatesValidIniWithExpectedDefaults() throws {
        try store.ensureSeeded(version: "8.4")
        let ini = paths.phpIni(version: "8.4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ini.path))
        let body = try String(contentsOf: ini, encoding: .utf8)
        XCTAssertTrue(body.contains("memory_limit = 512M"))
        XCTAssertTrue(body.contains("opcache.enable = 1"))
    }

    func testSeedIsIdempotentAndDoesNotClobberEdits() throws {
        try store.write(version: "8.1", contents: "memory_limit = 1G\n")
        try store.ensureSeeded(version: "8.1") // must NOT overwrite the user's content
        XCTAssertEqual(try store.read(version: "8.1"), "memory_limit = 1G\n")
    }

    func testWriteKeepsBackupOfPreviousContent() throws {
        try store.write(version: "8.3", contents: "memory_limit = 256M\n")
        try store.write(version: "8.3", contents: "memory_limit = 768M\n")
        XCTAssertEqual(try store.read(version: "8.3"), "memory_limit = 768M\n")

        let bak = paths.phpIni(version: "8.3").appendingPathExtension("bak")
        XCTAssertEqual(try String(contentsOf: bak, encoding: .utf8), "memory_limit = 256M\n")
    }

    func testResetRestoresTemplate() throws {
        try store.write(version: "8.4", contents: "memory_limit = 64M\n")
        try store.resetToDefault(version: "8.4")
        XCTAssertEqual(try store.read(version: "8.4"), PHPIniTemplate.default)
    }

    func testRestoreBackupRevertsLastWrite() throws {
        try store.write(version: "8.4", contents: "good = 1\n")
        try store.write(version: "8.4", contents: "broken\n")
        XCTAssertTrue(try store.restoreBackup(version: "8.4"))
        XCTAssertEqual(try store.read(version: "8.4"), "good = 1\n")
    }

    func testRestoreBackupNoOpWithoutBackup() throws {
        try store.ensureSeeded(version: "8.4")
        XCTAssertFalse(try store.restoreBackup(version: "8.4"))
    }

    func testValidateDegradesToNilWhenPHPBinaryAbsent() {
        // No php binary is staged under the temp root, so validation cannot run and must not block.
        XCTAssertNil(store.validate(version: "8.4", contents: "garbage ][ {{{\n"))
    }
}
