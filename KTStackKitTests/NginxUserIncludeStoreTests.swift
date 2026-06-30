import XCTest
@testable import KTStackKit

final class NginxUserIncludeStoreTests: XCTestCase {
    private var root: URL!
    private var paths: AppSupportPaths!
    private var store: NginxUserIncludeStore!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-nginx-extra-\(UUID().uuidString)")
        paths = AppSupportPaths(root: root)
        store = NginxUserIncludeStore(paths: paths)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - A1.1 Path tests

    func testNginxUserConfPathIsInsideNginxConfigDir() {
        XCTAssertEqual(paths.nginxUserConf.lastPathComponent, "nginx-extra.conf")
        XCTAssertTrue(paths.nginxUserConf.path.hasPrefix(paths.nginxConfigDir.path))
    }

    func testNginxUserConfIsNotUnderSitesEnabled() {
        XCTAssertFalse(paths.nginxUserConf.path.hasPrefix(paths.sitesEnabled.path))
    }

    // MARK: - A1.2 Template test

    func testNginxUserIncludeTemplateIsAllCommentsAndContainsMarker() {
        let template = NginxUserIncludeTemplate.default
        let lines = template.components(separatedBy: "\n")
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            XCTAssertTrue(
                line.trimmingCharacters(in: .whitespaces).hasPrefix("#"),
                "Expected comment line but got: \(line)"
            )
        }
        XCTAssertTrue(template.contains("# KTStack"), "Template must contain '# KTStack' marker")
    }

    // MARK: - A2.1 Store behavior tests (9 tests)

    func testEnsureSeededCreatesFileWithExpectedMarker() throws {
        try store.ensureSeeded()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.nginxUserConf.path))
        let content = try String(contentsOf: paths.nginxUserConf, encoding: .utf8)
        XCTAssertTrue(content.contains("# KTStack"))
    }

    func testEnsureSeededIsIdempotentAndDoesNotClobberEdits() throws {
        try store.write(contents: "custom\n")
        try store.ensureSeeded()
        XCTAssertEqual(try store.read(), "custom\n")
    }

    func testReadAbsentFileReturnsSeedTemplate() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.nginxUserConf.path))
        let content = try store.read()
        XCTAssertEqual(content, NginxUserIncludeTemplate.default)
    }

    func testReadExistingFileReturnsCurrentContent() throws {
        try store.write(contents: "user content\n")
        XCTAssertEqual(try store.read(), "user content\n")
    }

    func testWriteCreatesBackupOfPreviousContent() throws {
        try store.write(contents: "v1\n")
        try store.write(contents: "v2\n")
        let bak = paths.nginxUserConf.appendingPathExtension("bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bak.path))
        XCTAssertEqual(try String(contentsOf: bak, encoding: .utf8), "v1\n")
    }

    func testFirstWriteNoBackupWhenFileAbsent() throws {
        try store.write(contents: "first\n")
        let bak = paths.nginxUserConf.appendingPathExtension("bak")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bak.path))
    }

    func testResetToDefaultRestoresTemplate() throws {
        try store.write(contents: "custom\n")
        try store.resetToDefault()
        XCTAssertEqual(try store.read(), NginxUserIncludeTemplate.default)
    }

    func testRestoreBackupRevertsActiveFile() throws {
        try store.write(contents: "good\n")
        try store.write(contents: "bad\n")
        try store.restoreBackup()
        XCTAssertEqual(try store.read(), "good\n")
    }

    func testRestoreBackupReturnsFalseWhenNoBakExists() throws {
        try store.ensureSeeded()
        let result = try store.restoreBackup()
        XCTAssertFalse(result)
    }
}
