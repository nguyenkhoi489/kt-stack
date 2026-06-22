import XCTest
@testable import KTStackKit

final class NodeSiteControllerSpecTests: XCTestCase {
    private let paths = AppSupportPaths(root: URL(fileURLWithPath: "/tmp/ktstack-node-test"))

    private func controller(versions: [String] = ["22.22.3"],
                            hasModules: Bool = true) -> NodeSiteController {
        NodeSiteController(paths: paths,
                           agents: LaunchAgentManager(paths: paths),
                           installedNodeVersions: { versions },
                           nodeModulesPresent: { _ in hasModules })
    }

    private func site(command: String? = "npm run dev", port: Int? = 3001) -> Site {
        Site(name: "app", path: "/Users/me/Sites/app", docroot: "/Users/me/Sites/app",
             domain: "app.test", phpVersion: "8.4", type: .node,
             nodePort: port, nodeCommand: command, nodeEnabled: true)
    }

    func testBuildSpecCarriesLabelEnvWorkingDirAndLogs() throws {
        let spec = try XCTUnwrap(controller().buildSpec(for: site(), version: "22.22.3"))
        XCTAssertEqual(spec.label, "com.ktstack.node.app.test")
        XCTAssertEqual(spec.environment["PORT"], "3001")
        XCTAssertEqual(spec.environment["NODE_ENV"], "development")
        XCTAssertEqual(spec.workingDirectory, "/Users/me/Sites/app")
        XCTAssertEqual(spec.stdoutPath, paths.nodeOutLog("app.test").path)
        XCTAssertEqual(spec.stderrPath, paths.nodeErrLog("app.test").path)
        XCTAssertTrue(spec.keepAliveOnCrash)
    }

    func testBuildSpecResolvesNpmToVersionedRuntimeBin() throws {
        let spec = try XCTUnwrap(controller().buildSpec(for: site(command: "npm run dev"), version: "22.22.3"))
        let npm = paths.runtimeBin("node", "22.22.3").appendingPathComponent("npm").path
        XCTAssertEqual(spec.programArguments, [npm, "run", "dev"])
        XCTAssertTrue(spec.environment["PATH"]?.hasPrefix(paths.runtimeBin("node", "22.22.3").path) ?? false)
    }

    func testBuildSpecResolvesNodeServerCommand() throws {
        let spec = try XCTUnwrap(controller().buildSpec(for: site(command: "node server.js"), version: "22.22.3"))
        let node = paths.runtimeBin("node", "22.22.3").appendingPathComponent("node").path
        XCTAssertEqual(spec.programArguments, [node, "server.js"])
    }

    func testBuildSpecNilWhenNoPort() {
        XCTAssertNil(controller().buildSpec(for: site(port: nil), version: "22.22.3"))
    }

    func testReadinessNeedsRuntimeWhenNoNodeInstalled() {
        XCTAssertEqual(controller(versions: []).readiness(for: site()), .needsRuntime)
    }

    func testReadinessNeedsCommandWhenCommandMissing() {
        XCTAssertEqual(controller().readiness(for: site(command: nil)), .needsCommand)
        XCTAssertEqual(controller().readiness(for: site(command: "   ")), .needsCommand)
    }

    func testReadinessNeedsInstallWhenNodeModulesMissing() {
        XCTAssertEqual(controller(hasModules: false).readiness(for: site()), .needsInstall)
    }

    func testReadinessReadyWhenAllSatisfied() {
        XCTAssertEqual(controller().readiness(for: site()), .ready(version: "22.22.3"))
    }

    func testReadinessPicksNumericallyHighestNodeVersion() {
        let multi = controller(versions: ["18.0.0", "9.0.0", "22.22.3"])
        XCTAssertEqual(multi.readiness(for: site()), .ready(version: "22.22.3"))
    }

    func testReadinessPrecedenceRuntimeBeforeCommandBeforeModules() {
        let blocked = controller(versions: [], hasModules: false)
        XCTAssertEqual(blocked.readiness(for: site(command: nil)), .needsRuntime)
    }

    func testBadgeLabelMapping() {
        XCTAssertEqual(NodeSiteController.State.running.badgeLabel, "Running")
        XCTAssertEqual(NodeSiteController.State.crashed.badgeLabel, "Crashed")
        XCTAssertEqual(NodeSiteController.State.needsRuntime.badgeLabel, "Needs Node")
        XCTAssertEqual(NodeSiteController.State.needsInstall.badgeLabel, "Needs Install")
        XCTAssertEqual(NodeSiteController.State.needsCommand.badgeLabel, "Needs Command")
        XCTAssertTrue(NodeSiteController.State.running.isHealthy)
        XCTAssertFalse(NodeSiteController.State.crashed.isHealthy)
    }

    func testTokenizeHandlesExtraWhitespace() {
        XCTAssertEqual(NodeSiteController.tokenize("npm   run  dev"), ["npm", "run", "dev"])
        XCTAssertEqual(NodeSiteController.tokenize(""), [])
    }
}
