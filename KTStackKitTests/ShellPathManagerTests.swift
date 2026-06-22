import XCTest
@testable import KTStackKit

final class ShellPathManagerTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-shell-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    func testRCPatcherAddsHashStampedBlockIdempotently() throws {
        let patcher = ShellRCPatcher(exportLine: "export PATH=\"$PATH:/x/shims\"")
        let once = try patcher.contentWithBlock(in: "# user rc\n", file: ".zshrc")
        XCTAssertTrue(once.contains(ShellRCPatcher.startPrefix))
        XCTAssertTrue(patcher.containsValidBlock(in: once, file: ".zshrc"))
        let twice = try patcher.contentWithBlock(in: once, file: ".zshrc")
        let count = twice.components(separatedBy: ShellRCPatcher.startPrefix).count - 1
        XCTAssertEqual(count, 1, "re-applying must not stack blocks")
    }

    func testRCPatcherRefusesTamperedBlock() throws {
        let patcher = ShellRCPatcher(exportLine: "export PATH=\"$PATH:/x/shims\"")
        let applied = try patcher.contentWithBlock(in: "", file: ".zshrc")
        let tampered = applied.replacingOccurrences(of: "/x/shims", with: "/evil")
        XCTAssertThrowsError(try patcher.contentRemovingBlock(from: tampered, file: ".zshrc"))
    }

    func testRCPatcherRefusesDuplicateBlocks() throws {
        let patcher = ShellRCPatcher(exportLine: "export PATH=\"$PATH:/x/shims\"")
        let block = patcher.renderedBlock()
        let doubled = block + "\n" + block + "\n"
        XCTAssertThrowsError(try patcher.contentRemovingBlock(from: doubled, file: ".zshrc"))
    }

    private func makeHelper() throws -> URL {
        let helper = tmp.appendingPathComponent("ktstack-resolve")
        try "#!/bin/sh\necho noop\n".write(to: helper, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        return helper
    }

    func testEnableWritesHardenedShimsAndPatchesZshrc() async throws {
        let home = tmp.appendingPathComponent("home")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let paths = AppSupportPaths(root: tmp.appendingPathComponent("support"))
        let manager = ShellPathManager(paths: paths, helperSource: try makeHelper(), home: home)

        try await manager.enable(provisionComposer: false)

        let dirPerms = try fm.attributesOfItem(atPath: paths.shimBinDir.path)[.posixPermissions] as? Int
        XCTAssertEqual(dirPerms, 0o755)
        for shim in ["php", "composer", "node", "wp", "ktstack-resolve"] {
            let url = paths.shimBinDir.appendingPathComponent(shim)
            XCTAssertTrue(fm.isExecutableFile(atPath: url.path), "\(shim) missing/not executable")
        }
        let zshrc = try String(contentsOf: home.appendingPathComponent(".zshrc"), encoding: .utf8)
        XCTAssertTrue(zshrc.contains(ShellRCPatcher.startPrefix))
        XCTAssertTrue(zshrc.contains("export PATH=\"\(paths.shimBinDir.path):$PATH\""),
                      "shim dir must be prepended so KTStack runtimes win over system PATH")

        let status = manager.status()
        XCTAssertTrue(status.enabled)
        XCTAssertTrue(status.shellsPatched.contains(".zshrc"))
    }

    func testReEnableBacksUpExistingRC() async throws {
        let home = tmp.appendingPathComponent("home")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let paths = AppSupportPaths(root: tmp.appendingPathComponent("support"))
        let manager = ShellPathManager(paths: paths, helperSource: try makeHelper(), home: home)

        try await manager.enable(provisionComposer: false)
        try await manager.enable(provisionComposer: false)

        let backups = try fm.contentsOfDirectory(atPath: home.path)
            .filter { $0.hasPrefix(".zshrc.ktstack.bak-") }
        XCTAssertFalse(backups.isEmpty, "re-apply must back up the rc file")
    }

    func testDisableRemovesBlockAndShimDir() async throws {
        let home = tmp.appendingPathComponent("home")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let paths = AppSupportPaths(root: tmp.appendingPathComponent("support"))
        let manager = ShellPathManager(paths: paths, helperSource: try makeHelper(), home: home)

        try await manager.enable(provisionComposer: false)
        try manager.disable()

        let zshrc = try String(contentsOf: home.appendingPathComponent(".zshrc"), encoding: .utf8)
        XCTAssertFalseContains(zshrc, ShellRCPatcher.startPrefix)
        XCTAssertFalse(fm.fileExists(atPath: paths.shimBinDir.path))
        XCTAssertFalse(manager.status().enabled)
    }

    func testPHPShimsIsolateConfigButNodeDoesNot() throws {
        let paths = AppSupportPaths(root: tmp.appendingPathComponent("support"))
        let shims = ShellShimWriter(paths: paths).shims
        for name in ["php", "composer", "wp"] {
            let body = try XCTUnwrap(shims[name])
            XCTAssertTrue(body.contains("export PHPRC="), "\(name) must isolate PHPRC")
            XCTAssertTrue(body.contains("export PHP_INI_SCAN_DIR="), "\(name) must isolate PHP_INI_SCAN_DIR")
        }
        let node = try XCTUnwrap(shims["node"])
        XCTAssertFalse(node.contains("PHPRC"), "node shim must not touch PHP config")
    }

    func testDirectShimsFallBackToSystemBinaryWhenNoRuntime() throws {
        let paths = AppSupportPaths(root: tmp.appendingPathComponent("support"))
        let shims = ShellShimWriter(paths: paths).shims
        for name in ["node", "php"] {
            let body = try XCTUnwrap(shims[name])
            XCTAssertTrue(body.contains("command -v \(name)"),
                          "\(name) shim must fall back to the system binary when no KTStack runtime resolves")
            XCTAssertTrue(body.contains("grep -vxF \"\(paths.shimBinDir.path)\""),
                          "\(name) shim must drop its own shim dir before the system lookup")
        }
    }

    func testResolvedRuntimePreservesSystemPathInsteadOfResettingIt() throws {
        let paths = AppSupportPaths(root: tmp.appendingPathComponent("support"))
        let shims = ShellShimWriter(paths: paths).shims
        for name in ["node", "php", "composer", "wp"] {
            let body = try XCTUnwrap(shims[name])
            XCTAssertFalse(body.contains("export PATH=/usr/bin:/bin"),
                           "\(name) shim must not wipe system PATH or tools like gh/git/brew disappear for child processes")
            XCTAssertTrue(body.contains("export PATH=\"${target%/*}:$system_path\""),
                          "\(name) shim must prepend the runtime bin dir to the shim-stripped system PATH")
        }
    }

    func testComposerProvisionerRejectsUnverifiedCachedPhar() throws {
        let paths = AppSupportPaths(root: tmp.appendingPathComponent("support"))
        try fm.createDirectory(at: paths.composerPhar.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try "not a real phar".write(to: paths.composerPhar, atomically: true, encoding: .utf8)
        XCTAssertFalse(ComposerProvisioner(paths: paths).isProvisioned)
    }
}

private func XCTAssertFalseContains(_ haystack: String, _ needle: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(haystack.contains(needle), "unexpected \(needle)", file: file, line: line)
}
