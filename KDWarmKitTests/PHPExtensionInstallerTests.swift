import XCTest
@testable import KDWarmKit

/// Unit tests for the optional-extension install lifecycle: ini generation (plain vs Zend), placing a
/// `.so` WITHOUT wiping sibling extensions (red-team C1), the `extension_dir` scan-dir ini (C2),
/// uninstall removal, and the php-fpm `PHP_INI_SCAN_DIR` wiring. The network download + live FPM load
/// gate are exercised manually (Phase-3 step 4); these cover the pure file/wiring logic.
final class PHPExtensionInstallerTests: XCTestCase {

    private func tempPaths() throws -> AppSupportPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kdwarm-extinstall-\(UUID().uuidString)")
        let paths = AppSupportPaths(root: root)
        try paths.ensureDirectoryTree()
        return paths
    }

    private func writeFakeSO(_ name: String) throws -> URL {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).so")
        try Data("fake-so".utf8).write(to: f)
        return f
    }

    func testIniGenerationExtensionVsZend() throws {
        let installer = PHPExtensionInstaller(paths: try tempPaths())
        let imagick = installer.iniContent(forExtID: "imagick", phpVersion: "8.4")
        XCTAssertEqual(imagick, "extension=imagick.so\n")
        // Zend extensions need an ABSOLUTE path — extension_dir does not apply to zend_extension=.
        let xdebug = installer.iniContent(forExtID: "xdebug", phpVersion: "8.4")
        XCTAssertTrue(xdebug.hasPrefix("zend_extension=/"), "zend_extension must be an absolute path: \(xdebug)")
        XCTAssertTrue(xdebug.hasSuffix("/modules/xdebug.so\n"))
    }

    func testInstallPlacesSoKeepsSiblings() throws {
        let paths = try tempPaths()
        let installer = PHPExtensionInstaller(paths: paths)
        let modules = paths.phpModulesDir(version: "8.4")
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        // Pre-existing sibling extension already installed.
        let sibling = modules.appendingPathComponent("apcu.so")
        try Data("sibling".utf8).write(to: sibling)

        // Install imagick from a local .so → its .so + ini land, the sibling is untouched (C1).
        let src = try writeFakeSO("imagick")
        try installer.placeSharedObject(from: src, extID: "imagick", phpVersion: "8.4")
        try installer.finishInstall(extID: "imagick", phpVersion: "8.4")

        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path), "sibling apcu.so must survive")
        XCTAssertTrue(FileManager.default.fileExists(atPath: modules.appendingPathComponent("imagick.so").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.extensionIniURL(extID: "imagick", phpVersion: "8.4").path))
    }

    func testExtensionDirIniWritten() throws {
        let paths = try tempPaths()
        let installer = PHPExtensionInstaller(paths: paths)
        try installer.writeExtensionDirIni(phpVersion: "8.4")
        let ini = installer.extensionDirIniURL(phpVersion: "8.4")
        XCTAssertEqual(ini.lastPathComponent, "00-extension-dir.ini")
        let content = try String(contentsOf: ini, encoding: .utf8)
        XCTAssertTrue(content.contains("extension_dir"), content)
        XCTAssertTrue(content.contains(paths.phpModulesDir(version: "8.4").path), content)
    }

    func testUninstallRemovesIniAndSo() throws {
        let paths = try tempPaths()
        let installer = PHPExtensionInstaller(paths: paths)
        try FileManager.default.createDirectory(at: paths.phpModulesDir(version: "8.4"), withIntermediateDirectories: true)
        try installer.placeSharedObject(from: try writeFakeSO("imagick"), extID: "imagick", phpVersion: "8.4")
        try installer.finishInstall(extID: "imagick", phpVersion: "8.4")

        try installer.uninstall("imagick", phpVersion: "8.4")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.phpModulesDir(version: "8.4").appendingPathComponent("imagick.so").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.extensionIniURL(extID: "imagick", phpVersion: "8.4").path))
    }

    func testSpecCarriesIniScanDirEnv() throws {
        let paths = try tempPaths()
        let controller = PHPFPMController(paths: paths,
                                          agents: LaunchAgentManager(paths: paths),
                                          poolName: "8.4")
        let spec = controller.spec(poolConf: paths.phpFpmPool("8.4"))
        XCTAssertEqual(spec.environment["PHP_INI_SCAN_DIR"], paths.phpExtConfDir(version: "8.4").path)
    }
}
