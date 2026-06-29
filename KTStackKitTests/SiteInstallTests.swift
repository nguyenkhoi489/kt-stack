import XCTest
@testable import KTStackKit

final class SiteInstallTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-install-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    private func request(kind: NewSiteKind) -> NewSiteRequest {
        NewSiteRequest(
            name: "demo",
            kind: kind,
            phpVersion: "8.4",
            folder: tmp.appendingPathComponent("demo"),
            domain: "demo.test",
            databaseName: "demo",
            siteTitle: "Demo",
            adminPassword: "Sup3rSecret!pw"
        )
    }

    func testCreateDatabaseFailsOnExistingDatabase() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KTSTACK_DB_IT"] == "1",
            "Set KTSTACK_DB_IT=1 with the MySQL engine running on :3306."
        )
        let provisioner = DatabaseProvisioner(ensureEngine: {})
        let name = "ktstack_it_\(UUID().uuidString.prefix(8))"
        try await provisioner.createDatabase(name)
        defer { Task { try? await provisioner.dropDatabase(name) } }
        var thrown: Error?
        do { try await provisioner.createDatabase(name) } catch { thrown = error }
        XCTAssertEqual(
            thrown as? DatabaseProvisioner.ProvisionError,
            .alreadyExists(name),
            "duplicate name must throw, never adopt an existing DB (H6)"
        )
        try await provisioner.dropDatabase(name)
        let exists = try await provisioner.exists(name)
        XCTAssertFalse(exists, "rollback must drop the created DB")
    }

    func testWordPressInstallArgsNeverCarryAdminPassword() {
        let args = WordPressInstaller.coreInstallArgs(phar: "/x/wp.phar", path: "--path=/x", request: request(kind: .wordpress))
        XCTAssertFalse(args.contains { $0.contains("Sup3rSecret!pw") }, "admin password must never ride in argv (H3)")
        XCTAssertTrue(args.contains("--prompt=admin_password"), "password must be read from stdin via --prompt")
        XCTAssertTrue(args.contains("--url=https://demo.test"))
    }

    func testLaravelEnvRewriteSetsManagedDatabaseFields() throws {
        let folder = tmp.appendingPathComponent("laravel")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = """
        APP_NAME=Laravel
        APP_URL=http://localhost
        DB_CONNECTION=sqlite
        DB_HOST=127.0.0.1
        # DB_DATABASE=laravel
        """
        try original.write(to: folder.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        try LaravelInstaller.configureEnv(in: folder, request: request(kind: .laravel))

        let env = try String(contentsOf: folder.appendingPathComponent(".env"), encoding: .utf8)
        XCTAssertTrue(env.contains("DB_CONNECTION=mysql"))
        XCTAssertTrue(env.contains("DB_DATABASE=demo"))
        XCTAssertTrue(env.contains("DB_USERNAME=root"))
        XCTAssertTrue(env.contains("DB_PASSWORD="))
        XCTAssertTrue(env.contains("APP_URL=https://demo.test"))
        XCTAssertTrue(env.contains("# DB_DATABASE=laravel"), "commented lines must be left untouched")
    }

    func testLaravelEnvRewriteThrowsWhenEnvMissing() throws {
        let folder = tmp.appendingPathComponent("noenv")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertThrowsError(try LaravelInstaller.configureEnv(in: folder, request: request(kind: .laravel)))
    }

    func testLaravelCreateProjectArgsIgnoreMissingXMLWriterOnly() {
        let missing = LaravelInstaller.createProjectArgs(
            composerPhar: "/x/composer.phar",
            name: "demo",
            loadedModules: ["xml", "dom"]
        )
        XCTAssertTrue(missing.contains("--ignore-platform-req=ext-xmlwriter"))

        let present = LaravelInstaller.createProjectArgs(
            composerPhar: "/x/composer.phar",
            name: "demo",
            loadedModules: ["xmlwriter"]
        )
        XCTAssertFalse(present.contains("--ignore-platform-req=ext-xmlwriter"))
    }

    func testInstallCommandRunnerUsesManagedPHPIniWhenPresent() throws {
        let phpIni = tmp.appendingPathComponent("php.ini")
        try "memory_limit = 512M\n".write(to: phpIni, atomically: true, encoding: .utf8)

        let runner = InstallCommandRunner(php: URL(fileURLWithPath: "/x/php"), phpIni: phpIni)
        XCTAssertEqual(
            runner.phpArguments(["/x/wp.phar", "core", "download"]),
            ["-c", phpIni.path, "/x/wp.phar", "core", "download"]
        )
    }

    func testInstallCommandRunnerSkipsMissingManagedPHPIni() {
        let phpIni = tmp.appendingPathComponent("missing.ini")
        let runner = InstallCommandRunner(php: URL(fileURLWithPath: "/x/php"), phpIni: phpIni)
        XCTAssertEqual(
            runner.phpArguments(["/x/composer.phar", "create-project"]),
            ["/x/composer.phar", "create-project"]
        )
    }

    func testPharProvisionerRejectsUnverifiedCachedPhar() throws {
        let paths = AppSupportPaths(root: tmp.appendingPathComponent("as"))
        let provisioner = PharProvisioner.wpCli(paths: paths)
        try fm.createDirectory(at: provisioner.dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "garbage".write(to: provisioner.dest, atomically: true, encoding: .utf8)
        XCTAssertFalse(provisioner.isProvisioned)
    }

    func testInstallServiceRemovesFolderWhenScaffoldFails() async throws {
        let folder = tmp.appendingPathComponent("demo")
        let service = SiteInstallService(database: DatabaseProvisioner(port: 0, ensureEngine: {}))
        let req = NewSiteRequest(
            name: "demo",
            kind: .laravel,
            phpVersion: "8.4",
            folder: folder,
            domain: "demo.test",
            databaseName: nil
        )
        do {
            _ = try await service.install(req, installer: FailingInstaller(), register: { _ in
                XCTFail("register must not run after scaffold failure")
                throw InstallError.folderExists("x")
            }, emit: { _ in })
            XCTFail("expected scaffold failure")
        } catch {
            XCTAssertFalse(fm.fileExists(atPath: folder.path), "folder must be rolled back")
        }
    }

    func testInstallServiceThrowsWhenFolderAlreadyExists() async throws {
        let folder = tmp.appendingPathComponent("taken")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let service = SiteInstallService(database: DatabaseProvisioner(port: 0, ensureEngine: {}))
        let req = NewSiteRequest(
            name: "taken",
            kind: .laravel,
            phpVersion: "8.4",
            folder: folder,
            domain: "taken.test",
            databaseName: nil
        )
        var thrown: Error?
        do {
            _ = try await service.install(req, installer: FailingInstaller(), register: { _ in
                throw InstallError.folderExists("x")
            }, emit: { _ in })
        } catch { thrown = error }
        XCTAssertEqual(thrown as? InstallError, .folderExists("taken"))
        XCTAssertTrue(fm.fileExists(atPath: folder.path), "pre-existing folder must NOT be deleted")
    }
}

private struct FailingInstaller: SiteInstaller {
    func scaffold(into _: URL, request _: NewSiteRequest, emit _: @Sendable (String) -> Void) async throws {
        throw InstallError.folderExists("scaffold blew up")
    }
}
