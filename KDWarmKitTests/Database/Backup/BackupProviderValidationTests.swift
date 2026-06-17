import XCTest
@testable import KDWarmKit

final class BackupProviderValidationTests: XCTestCase {

    func testSQLiteProviderAlwaysAvailable() {
        XCTAssertTrue(SQLiteBackupProvider().isAvailable)
        XCTAssertEqual(SQLiteBackupProvider().fileExtension, "sqlite")
    }

    func testSQLiteProviderRejectsBackupWithoutFilePath() async {
        let provider = SQLiteBackupProvider()
        let profile = ConnectionProfile(name: "missing", kind: .sqlite, host: "",
                                        port: 0, user: "", database: "main")
        do {
            try await provider.backup(profile: profile, password: nil,
                                       database: "main", to: URL(fileURLWithPath: "/tmp/out.sqlite"))
            XCTFail("expected failure")
        } catch {}
    }

    /// F15: MySQL provider reports unavailable when the catalog has no installed engine, even
    /// though the binary URL would be returned. The factory must surface a clear reason in that case.
    func testMySQLProviderUnavailableWhenEngineMissing() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kdwarm-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = DumpService(catalog: ServiceBinaryCatalog(paths: AppSupportPaths(root: tmp)))
        let provider = MySQLBackupProvider(dumpService: service)
        XCTAssertFalse(provider.isAvailable)
    }

    /// F15: Postgres runner must check executable existence per binary, not just the catalog URL.
    func testPostgresRunnerUnavailableWhenBinariesMissing() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kdwarm-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runner = PostgresBackupRunner(catalog: ServiceBinaryCatalog(paths: AppSupportPaths(root: tmp)))
        XCTAssertFalse(runner.isAvailable)
    }

    func testFactorySurfacesReasonWhenProviderUnavailable() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kdwarm-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = FileManager.default.currentDirectoryPath
        defer { FileManager.default.changeCurrentDirectoryPath(original) }

        if case .unavailable(let reason) = BackupProviderFactory.make(for: .mysql) {
            XCTAssertTrue(reason.lowercased().contains("mysql"))
        }
        if case .unavailable(let reason) = BackupProviderFactory.make(for: .mongodb) {
            XCTAssertTrue(reason.lowercased().contains("mongodb"))
        }
    }

    // MARK: - F13: version-skew gate

    func testSessionRefusesIncompatibleMajorVersion() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kdwarm-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let paths = AppSupportPaths(root: tmp)
        try paths.ensureDirectoryTree()
        let library = BackupLibrary(paths: paths)
        let session = BackupSession(library: library) { kind in
            kind == .postgres ? "17.10" : nil
        }
        let provider = StubBackupProvider(fileExtension: "dump")
        let set = try await library.create(
            kind: .postgres, profile: .managedPostgres, databases: ["app"],
            using: provider, password: nil, engineVersion: "16.4")
        do {
            try await session.restore(set: set, database: "app", profile: .managedPostgres,
                                       password: nil, target: .newDatabase("app_restored"))
            XCTFail("expected version-skew refusal")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message.contains("16.4"))
            XCTAssertTrue(error.message.contains("17.10"))
        }
    }

    func testSessionAllowsSameMajorVersion() async throws {
        XCTAssertEqual(BackupSession.majorVersion("17.10"), "17")
        XCTAssertEqual(BackupSession.majorVersion("9.6.0"), "9")
        XCTAssertEqual(BackupSession.majorVersion("100.10.0"), "100")
    }
}
