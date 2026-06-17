import XCTest
@testable import KDWarmKit

final class BackupLibraryTests: XCTestCase {

    private var paths: AppSupportPaths!
    private var library: BackupLibrary!
    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kdwarm-backup-tests-\(UUID().uuidString)", isDirectory: true)
        paths = AppSupportPaths(root: root)
        try paths.ensureDirectoryTree()
        library = BackupLibrary(paths: paths)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    func testCreateListDeleteRoundTrip() async throws {
        let provider = StubBackupProvider()
        let set = try await library.create(
            kind: .mysql, profile: .managedMySQL, databases: ["app", "logs"],
            using: provider, password: nil, engineVersion: "9.6.0")
        XCTAssertEqual(library.list().count, 1)
        XCTAssertEqual(library.list().first?.id, set.id)
        XCTAssertEqual(library.list().first?.databases, ["app", "logs"])
        XCTAssertGreaterThan(set.sizeBytes, 0)

        try library.delete(set)
        XCTAssertTrue(library.list().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.backupSetDir(set.id).path))
    }

    /// F11: manifest corruption must not hide on-disk sets. Rebuild from each set dir's meta.json.
    func testCorruptManifestRebuildsFromOnDiskMeta() async throws {
        let provider = StubBackupProvider()
        let setA = try await library.create(kind: .mysql, profile: .managedMySQL,
                                             databases: ["a"], using: provider, password: nil)
        let setB = try await library.create(kind: .mysql, profile: .managedMySQL,
                                             databases: ["b"], using: provider, password: nil)
        try Data("not-json".utf8).write(to: paths.backupManifest)

        let rebuilt = library.list()
        let ids = Set(rebuilt.map(\.id))
        XCTAssertTrue(ids.contains(setA.id))
        XCTAssertTrue(ids.contains(setB.id))

        let manifestData = try Data(contentsOf: paths.backupManifest)
        XCTAssertFalse(manifestData.isEmpty)
    }

    /// F11: a manifest entry whose set dir has been hand-deleted should be pruned, not surfaced.
    func testListPrunesEntriesWithMissingSetDirectory() async throws {
        let provider = StubBackupProvider()
        let set = try await library.create(kind: .mysql, profile: .managedMySQL,
                                            databases: ["a"], using: provider, password: nil)
        try FileManager.default.removeItem(at: paths.backupSetDir(set.id))

        XCTAssertTrue(library.list().isEmpty)
    }

    func testExportThenImportReproducesSet() async throws {
        let provider = StubBackupProvider()
        let original = try await library.create(kind: .mysql, profile: .managedMySQL,
                                                 databases: ["app"], using: provider, password: nil)
        let exportURL = root.appendingPathComponent("exported")
        try library.export(original, to: exportURL)
        try library.delete(original)
        XCTAssertTrue(library.list().isEmpty)

        let imported = try library.importSet(from: exportURL)
        XCTAssertEqual(imported.databases, ["app"])
        XCTAssertEqual(library.list().count, 1)
        let importedFile = paths.backupSetDir(imported.id).appendingPathComponent("app.stub")
        XCTAssertEqual(try String(contentsOf: importedFile), "app")
    }

    // MARK: - F8: filesystem path safety

    func testSafeArtifactURLRejectsDotDot() {
        let setDir = root.appendingPathComponent("set")
        XCTAssertThrowsError(try BackupLibrary.safeArtifactURL(
            database: "..", fileExtension: "sql", in: setDir))
    }

    func testSafeArtifactURLRejectsDot() {
        let setDir = root.appendingPathComponent("set")
        XCTAssertThrowsError(try BackupLibrary.safeArtifactURL(
            database: ".", fileExtension: "sql", in: setDir))
    }

    func testSafeArtifactURLRejectsPathSeparator() {
        let setDir = root.appendingPathComponent("set")
        XCTAssertThrowsError(try BackupLibrary.safeArtifactURL(
            database: "a/b", fileExtension: "sql", in: setDir))
    }

    func testSafeArtifactURLAcceptsNormalName() throws {
        let setDir = root.appendingPathComponent("set")
        let url = try BackupLibrary.safeArtifactURL(database: "app", fileExtension: "sql", in: setDir)
        XCTAssertEqual(url.lastPathComponent, "app.sql")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path,
                       setDir.standardizedFileURL.path)
    }

    func testSafeArtifactURLHandlesEmptyExtensionForDirectoryArtifacts() throws {
        let setDir = root.appendingPathComponent("set")
        let url = try BackupLibrary.safeArtifactURL(database: "app", fileExtension: "", in: setDir)
        XCTAssertEqual(url.lastPathComponent, "app")
    }
}
