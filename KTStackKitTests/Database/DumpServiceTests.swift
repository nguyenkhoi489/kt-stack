import XCTest
@testable import KTStackKit

final class DumpServiceTests: XCTestCase {
    func testValidateIdentifierAcceptsNormalNames() throws {
        try DumpService.validateIdentifier("app_db", label: "database")
        try DumpService.validateIdentifier("users", label: "table")
    }

    func testValidateIdentifierRejectsInjectionVectors() {
        XCTAssertThrowsError(try DumpService.validateIdentifier("", label: "database"))
        XCTAssertThrowsError(try DumpService.validateIdentifier("-x", label: "database")) // looks like a flag
        XCTAssertThrowsError(try DumpService.validateIdentifier("a=b", label: "database")) // option smuggling
        XCTAssertThrowsError(try DumpService.validateIdentifier("a/b", label: "database")) // path separator
        XCTAssertThrowsError(try DumpService.validateIdentifier("a`b", label: "database")) // backtick
        XCTAssertThrowsError(try DumpService.validateIdentifier("a\nb", label: "database")) // newline → ini break
        XCTAssertThrowsError(try DumpService.validateIdentifier("a\u{0}b", label: "database")) // NUL
        XCTAssertThrowsError(try DumpService.validateIdentifier(
            String(repeating: "x", count: 65),
            label: "database"
        )) // too long
    }

    func testValidateHostAllowsAddressesRejectsJunk() throws {
        try DumpService.validateHost("127.0.0.1")
        try DumpService.validateHost("::1")
        try DumpService.validateHost("db.example.com")
        XCTAssertThrowsError(try DumpService.validateHost("-h"))
        XCTAssertThrowsError(try DumpService.validateHost("a b"))
        XCTAssertThrowsError(try DumpService.validateHost("a=b"))
    }

    func testDefaultsContentCarriesCredentials() throws {
        let content = try DumpService.defaultsContent(
            user: "root",
            host: "127.0.0.1",
            port: 3306,
            password: "s3cr3t"
        )
        XCTAssertTrue(content.hasPrefix("[client]\n"))
        XCTAssertTrue(content.contains("user=root"))
        XCTAssertTrue(content.contains("host=127.0.0.1"))
        XCTAssertTrue(content.contains("port=3306"))
        XCTAssertTrue(content.contains("password=s3cr3t"))
    }

    func testDefaultsContentOmitsPasswordWhenNil() throws {
        let content = try DumpService.defaultsContent(
            user: "root",
            host: "127.0.0.1",
            port: 3306,
            password: nil
        )
        XCTAssertFalse(content.contains("password="))
    }

    func testDefaultsContentRejectsNewlinePassword() {
        XCTAssertThrowsError(try DumpService.defaultsContent(
            user: "root",
            host: "127.0.0.1",
            port: 3306,
            password: "bad\npass"
        ))
    }

    func testDefaultsContentEmitsSSLModeFromTLSMode() throws {
        let pairs: [(TLSMode, String)] = [
            (.disable, "DISABLED"), (.prefer, "PREFERRED"),
            (.require, "REQUIRED"), (.verifyFull, "VERIFY_IDENTITY"),
        ]
        for (mode, expected) in pairs {
            let content = try DumpService.defaultsContent(
                user: "root",
                host: "db.example.com",
                port: 3306,
                password: nil,
                tlsMode: mode
            )
            XCTAssertTrue(
                content.contains("ssl-mode=\(expected)"),
                "expected ssl-mode=\(expected) for \(mode)"
            )
        }
    }

    func testEnsureDumpNotEmptyThrowsOnZeroBytes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-empty-dump-\(UUID().uuidString).sql")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try DumpService.ensureDumpNotEmpty(at: url, database: "app"))
    }

    func testEnsureDumpNotEmptyPassesOnContent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-dump-\(UUID().uuidString).sql")
        try "-- dump\nCREATE TABLE t(id INT);\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNoThrow(try DumpService.ensureDumpNotEmpty(at: url, database: "app"))
    }

    func testDefaultsFileIsWrittenMode0600() throws {
        let url = try DumpService.writeDefaultsFile(content: "[client]\nuser=root\n")
        defer { try? FileManager.default.removeItem(at: url) }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o600)
    }

    func testExportWithoutEngineThrowsEngineNotInstalled() async throws {
        // Point the catalog at an empty support dir → no installed engine → nil binary.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let service = DumpService(
            catalog: ServiceBinaryCatalog(paths: AppSupportPaths(root: tmp)),
            systemToolSearchPaths: []
        )
        XCTAssertFalse(service.isEngineInstalled)

        do {
            try await service.export(
                profile: .managedMySQL,
                password: nil,
                database: "app",
                table: nil,
                to: tmp.appendingPathComponent("out.sql")
            )
            XCTFail("expected engineNotInstalled")
        } catch let error as DatabaseError {
            XCTAssertEqual(error, .engineNotInstalled(kind: "MySQL"))
        }
    }

    func testCreateDatabaseWithoutEngineThrowsEngineNotInstalled() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let service = DumpService(
            catalog: ServiceBinaryCatalog(paths: AppSupportPaths(root: tmp)),
            systemToolSearchPaths: []
        )
        do {
            try await service.createDatabase(profile: .managedMySQL, password: nil, database: "app")
            XCTFail("expected engineNotInstalled")
        } catch let error as DatabaseError {
            XCTAssertEqual(error, .engineNotInstalled(kind: "MySQL"))
        }
    }

    func testExportThenImportRoundTrip() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KTSTACK_DB_IT"] == "1",
            "Set KTSTACK_DB_IT=1 with the MySQL engine installed + running on :3306."
        )
        let catalog = ServiceBinaryCatalog(paths: AppSupportPaths())
        try XCTSkipUnless(catalog.isInstalled(.mysql), "MySQL engine not installed.")

        let service = DumpService(catalog: catalog)
        let driver = MySQLDriver(profile: .managedMySQL, password: nil)
        let suffix = UUID().uuidString.prefix(8)
        let source = "ktstack_dump_src_\(suffix)"
        let target = "ktstack_dump_dst_\(suffix)"
        defer {
            Task { _ = try? await driver.query("DROP DATABASE IF EXISTS \(self.bt(source))", database: nil) }
            Task { _ = try? await driver.query("DROP DATABASE IF EXISTS \(self.bt(target))", database: nil) }
        }

        _ = try await driver.query("CREATE DATABASE \(bt(source))", database: nil)
        _ = try await driver.query("CREATE TABLE \(bt(source)).t (id INT PRIMARY KEY)", database: nil)
        for i in 1...3 {
            _ = try await driver.query("INSERT INTO \(bt(source)).t VALUES (\(i))", database: nil)
        }

        let outFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-dump-\(suffix).sql")
        defer { try? FileManager.default.removeItem(at: outFile) }

        try await service.export(
            profile: .managedMySQL,
            password: nil,
            database: source,
            table: nil,
            to: outFile
        )
        try await service.importDump(
            profile: .managedMySQL,
            password: nil,
            database: target,
            from: outFile
        )

        let count = try await driver.query("SELECT COUNT(*) AS n FROM \(bt(target)).t", database: nil)
        XCTAssertEqual(count.rows.first?.first, .int(3))
    }

    private func bt(_ id: String) -> String {
        (try? SQLDialect.forKind(.mysql).quoteIdent(id)) ?? id
    }
}
