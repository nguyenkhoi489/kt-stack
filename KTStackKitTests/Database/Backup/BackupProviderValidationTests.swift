import XCTest
@testable import KTStackKit

final class BackupProviderValidationTests: XCTestCase {
    func testSQLiteProviderAlwaysAvailable() {
        XCTAssertTrue(SQLiteBackupProvider().isAvailable)
        XCTAssertEqual(SQLiteBackupProvider().fileExtension, "sqlite")
    }

    func testSQLiteProviderRejectsBackupWithoutFilePath() async {
        let provider = SQLiteBackupProvider()
        let profile = ConnectionProfile(
            name: "missing",
            kind: .sqlite,
            host: "",
            port: 0,
            user: "",
            database: "main"
        )
        do {
            try await provider.backup(
                profile: profile,
                password: nil,
                database: "main",
                to: URL(fileURLWithPath: "/tmp/out.sqlite")
            )
            XCTFail("expected failure")
        } catch {}
    }

    /// MySQL provider reports unavailable when neither the managed catalog nor the system search
    /// paths hold the client tools. System paths are pinned empty so a Homebrew install on the dev
    /// machine can't mask the assertion.
    func testMySQLProviderUnavailableWhenEngineMissing() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = DumpService(
            catalog: ServiceBinaryCatalog(paths: AppSupportPaths(root: tmp)),
            systemToolSearchPaths: []
        )
        let provider = MySQLBackupProvider(dumpService: service)
        XCTAssertFalse(provider.isAvailable)
        XCTAssertFalse(service.isEngineInstalled)
    }

    func testMySQLBackupAvailableViaSystemTools() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let stubDir = try Self.makeStubToolDir(tools: ["mysqldump", "mysql"])
        defer { try? FileManager.default.removeItem(at: stubDir) }

        let service = DumpService(
            catalog: ServiceBinaryCatalog(paths: AppSupportPaths(root: tmp)),
            systemToolSearchPaths: [stubDir]
        )
        XCTAssertTrue(MySQLBackupProvider(dumpService: service).isAvailable)
        XCTAssertTrue(service.isEngineInstalled)
        XCTAssertTrue(service.requiredBinariesPresent)
    }

    func testRequiredBinariesPresentNeedsBothClients() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let stubDir = try Self.makeStubToolDir(tools: ["mysqldump"])
        defer { try? FileManager.default.removeItem(at: stubDir) }

        let service = DumpService(
            catalog: ServiceBinaryCatalog(paths: AppSupportPaths(root: tmp)),
            systemToolSearchPaths: [stubDir]
        )
        XCTAssertTrue(service.isEngineInstalled)
        XCTAssertFalse(service.requiredBinariesPresent)
    }

    private static func makeStubToolDir(tools: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for tool in tools {
            let url = dir.appendingPathComponent(tool)
            try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return dir
    }

    /// Postgres runner must check executable existence per binary, not just the catalog URL.
    func testPostgresRunnerUnavailableWhenBinariesMissing() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let runner = PostgresBackupRunner(catalog: ServiceBinaryCatalog(paths: AppSupportPaths(root: tmp)))
        XCTAssertFalse(runner.isAvailable)
    }

    func testFactorySurfacesReasonWhenProviderUnavailable() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = FileManager.default.currentDirectoryPath
        defer { FileManager.default.changeCurrentDirectoryPath(original) }

        if case let .unavailable(reason) = BackupProviderFactory.make(for: .mysql) {
            XCTAssertTrue(reason.lowercased().contains("mysql"))
        }
        if case let .unavailable(reason) = BackupProviderFactory.make(for: .mongodb) {
            XCTAssertTrue(reason.lowercased().contains("mongodb"))
        }
    }

    func testSessionRefusesIncompatibleMajorVersion() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-session-\(UUID().uuidString)", isDirectory: true)
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
            using: provider, password: nil, engineVersion: "16.4"
        )
        do {
            try await session.restore(
                set: set,
                database: "app",
                profile: .managedPostgres,
                password: nil,
                target: .newDatabase("app_restored")
            )
            XCTFail("expected version-skew refusal")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message.contains("16.4"))
            XCTAssertTrue(error.message.contains("17.10"))
        }
    }

    func testSessionAllowsSameMajorVersion() {
        XCTAssertEqual(BackupSession.majorVersion("17.10"), "17")
        XCTAssertEqual(BackupSession.majorVersion("9.6.0"), "9")
        XCTAssertEqual(BackupSession.majorVersion("100.10.0"), "100")
    }

    func testUserDatabaseNamesDropsMySQLSystemSchemas() {
        let all = ["information_schema", "performance_schema", "mysql", "sys", "app", "blog"]
        XCTAssertEqual(BackupSession.userDatabaseNames(all, for: .mysql), ["app", "blog"])
    }

    func testUserDatabaseNamesDropsPostgresTemplates() {
        let all = ["template0", "template1", "postgres", "shop"]
        XCTAssertEqual(BackupSession.userDatabaseNames(all, for: .postgres), ["postgres", "shop"])
    }

    func testUserDatabaseNamesDropsMongoSystemDBs() {
        let all = ["admin", "local", "config", "myapp"]
        XCTAssertEqual(BackupSession.userDatabaseNames(all, for: .mongodb), ["myapp"])
    }

    func testUserDatabaseNamesPassesSQLiteThrough() {
        XCTAssertEqual(BackupSession.userDatabaseNames(["main"], for: .sqlite), ["main"])
    }

    func testUserDatabaseNamesIsCaseInsensitive() {
        XCTAssertEqual(
            BackupSession.userDatabaseNames(["INFORMATION_SCHEMA", "app"], for: .mysql),
            ["app"]
        )
    }
}
