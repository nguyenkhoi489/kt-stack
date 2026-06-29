import XCTest
@testable import KTStackKit

final class XdebugControllerTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-xdebug-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    private func controller(reload: @escaping (String) async throws -> Void = { _ in }) -> (XdebugController, AppSupportPaths) {
        let paths = AppSupportPaths(root: tmp)
        return (XdebugController(paths: paths, reloadPool: reload), paths)
    }

    private func controller(
        reload: @escaping (String) async throws -> Void,
        loadVerifier: @escaping XdebugController.LoadVerifier
    ) -> (XdebugController, AppSupportPaths) {
        let paths = AppSupportPaths(root: tmp)
        return (XdebugController(paths: paths, reloadPool: reload, loadVerifier: loadVerifier), paths)
    }

    func testGatingMatchesManifest() {
        let (controller, _) = controller()
        XCTAssertTrue(controller.isSupported(version: "8.4"))
        XCTAssertTrue(controller.isSupported(version: "8.1"))
        XCTAssertFalse(controller.isSupported(version: "7.4"))
    }

    func testEnableUnsupportedVersionThrowsAndTouchesNoConf() async {
        let (controller, _) = controller()
        var thrown: Error?
        do { try await controller.enable(version: "7.4") } catch { thrown = error }
        XCTAssertEqual(thrown as? XdebugController.XdebugError, .notSupported("7.4"))
        XCTAssertFalse(controller.isEnabled(version: "7.4"))
    }

    func testIniTargetsConfDNotMainPhpIni() {
        let (controller, paths) = controller()
        let conf = controller.confURL(version: "8.4")
        XCTAssertEqual(conf.lastPathComponent, "20-xdebug.ini")
        XCTAssertTrue(conf.path.hasPrefix(paths.phpExtConfDir(version: "8.4").path))
        XCTAssertNotEqual(conf.path, paths.phpIni(version: "8.4").path)

        let ini = controller.iniContent(version: "8.4")
        XCTAssertTrue(ini.contains("zend_extension="))
        XCTAssertTrue(ini.contains("xdebug.mode=debug"))
        XCTAssertTrue(ini.contains("xdebug.client_port=9003"))
    }

    func testEnableWithBadSharedObjectHashAbortsBeforeWritingConf() async throws {
        let (controller, paths) = controller()
        let module = paths.phpModulesDir(version: "8.4").appendingPathComponent("xdebug.so")
        try fm.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("bad-xdebug".utf8).write(to: module)
        try Data("known-good".utf8).write(to: module.appendingPathExtension("sha256"))

        do {
            try await controller.enable(version: "8.4")
            XCTFail("expected checksum failure")
        } catch let error as XdebugController.XdebugError {
            guard case .verificationFailed = error else {
                XCTFail("unexpected error \(error)")
                return
            }
            XCTAssertFalse(controller.isEnabled(version: "8.4"))
        }
    }

    func testDisableRemovesConfAndReloads() async throws {
        let reloaded = LockedFlag()
        let (controller, _) = controller(reload: { _ in reloaded.set() })
        let conf = controller.confURL(version: "8.4")
        try fm.createDirectory(at: conf.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "zend_extension=/x/xdebug.so\n".write(to: conf, atomically: true, encoding: .utf8)

        try await controller.disable(version: "8.4")
        XCTAssertFalse(fm.fileExists(atPath: conf.path))
        XCTAssertTrue(reloaded.value)
    }

    func testDisableRevertsConfWhenReloadFails() async {
        struct ReloadFail: Error {}
        let (controller, _) = controller(reload: { _ in throw ReloadFail() })
        let conf = controller.confURL(version: "8.4")
        try? fm.createDirectory(at: conf.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "zend_extension=/x/xdebug.so\n".write(to: conf, atomically: true, encoding: .utf8)

        do { try await controller.disable(version: "8.4"); XCTFail("expected reload failure") }
        catch { XCTAssertTrue(fm.fileExists(atPath: conf.path), "conf must be restored on reload failure") }
    }

    func testEnableRemovesNewConfWhenReloadFails() async throws {
        struct ReloadFail: Error {}
        let (controller, paths) = controller(
            reload: { _ in throw ReloadFail() },
            loadVerifier: { _ in (true, nil) }
        )
        let module = paths.phpModulesDir(version: "8.4").appendingPathComponent("xdebug.so")
        try fm.createDirectory(at: module.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("verified-xdebug".utf8).write(to: module)
        let checksum = try ChecksumVerifier.sha256(of: module)
        try checksum.write(to: module.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)

        do {
            try await controller.enable(version: "8.4")
            XCTFail("expected reload failure")
        } catch let error as XdebugController.XdebugError {
            guard case .rollbackFailed = error else {
                XCTFail("expected rollback failure, got \(error)")
                return
            }
            XCTAssertFalse(controller.isEnabled(version: "8.4"))
        }
    }

    func testLaunchJSONIsValidWithPort9003() throws {
        let json = IDEDebugConfigWriter.launchJSON(docroot: "/Users/x/Sites/demo \"quoted\"/public")
        let data = try XCTUnwrap(json.data(using: .utf8))
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let configs = try XCTUnwrap(parsed["configurations"] as? [[String: Any]])
        let config = try XCTUnwrap(configs.first)
        let mappings = try XCTUnwrap(config["pathMappings"] as? [String: String])
        XCTAssertEqual(config["port"] as? Int, 9003)
        XCTAssertEqual(mappings["/Users/x/Sites/demo \"quoted\"/public"], "${workspaceFolder}")
    }

    func testWriteVSCodePreservesExistingConfigurations() throws {
        let root = tmp.appendingPathComponent("project")
        let vscode = root.appendingPathComponent(".vscode", isDirectory: true)
        try fm.createDirectory(at: vscode, withIntermediateDirectories: true)
        let file = vscode.appendingPathComponent("launch.json")
        try """
        {"version":"0.2.0","configurations":[{"name":"Existing","type":"node","request":"launch"}]}
        """.write(to: file, atomically: true, encoding: .utf8)

        try IDEDebugConfigWriter().writeVSCode(
            projectRoot: root,
            docroot: root.appendingPathComponent("public")
        )

        let data = try Data(contentsOf: file)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let configs = try XCTUnwrap(parsed["configurations"] as? [[String: Any]])
        XCTAssertTrue(configs.contains { $0["name"] as? String == "Existing" })
        XCTAssertTrue(configs.contains { $0["name"] as? String == "Listen for Xdebug (KTStack)" })
    }

    func testWriteVSCodeMapsNestedDocrootToWorkspaceSubpath() throws {
        let root = tmp.appendingPathComponent("app")
        let publicRoot = root.appendingPathComponent("public")
        try fm.createDirectory(at: publicRoot, withIntermediateDirectories: true)

        try IDEDebugConfigWriter().writeVSCode(projectRoot: root, docroot: publicRoot)

        let file = root.appendingPathComponent(".vscode/launch.json")
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let configs = try XCTUnwrap(parsed["configurations"] as? [[String: Any]])
        let config = try XCTUnwrap(configs.first { $0["name"] as? String == "Listen for Xdebug (KTStack)" })
        let mappings = try XCTUnwrap(config["pathMappings"] as? [String: String])
        XCTAssertEqual(mappings[publicRoot.path], "${workspaceFolder}/public")
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() {
        lock.lock(); flag = true; lock.unlock()
    }

    var value: Bool {
        lock.lock(); defer { lock.unlock() }; return flag
    }
}
