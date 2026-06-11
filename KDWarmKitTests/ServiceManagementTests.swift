import XCTest
@testable import KDWarmKit

/// Unit tests for the launchd-controller service layer: plist rendering, restart/backoff policy,
/// health probes, port pre-flight, and the per-service path/identity mapping. These exercise the
/// pure logic; live `launchctl` bootstrap + DB init are verified manually (need a GUI session).
final class ServiceManagementTests: XCTestCase {
    private let paths = AppSupportPaths(root: URL(fileURLWithPath: "/tmp/kdwarm-svc-test"))

    // MARK: - ServiceKind identity

    func testServiceKindIdentityMapping() {
        XCTAssertEqual(ServiceKind.mysql.defaultPort, 3306)
        XCTAssertEqual(ServiceKind.redis.launchdLabel, "com.kdwarm.redis")
        XCTAssertEqual(ServiceKind.mailpit.binaryName, "mailpit")
        XCTAssertNil(ServiceKind.phpFpm.defaultPort)            // socket-based, no single port
        XCTAssertEqual(Set(ServiceKind.allCases).count, 7)
    }

    // MARK: - AppSupportPaths additions

    func testServiceDataAndLaunchAgentPaths() {
        XCTAssertEqual(paths.serviceData("mysql").lastPathComponent, "mysql")
        XCTAssertTrue(paths.serviceData("mysql").path.hasPrefix(paths.data.path))
        XCTAssertEqual(paths.serviceConfig("mysql", ext: "cnf").lastPathComponent, "mysql.cnf")
        XCTAssertEqual(paths.launchAgentPlist("com.kdwarm.redis").lastPathComponent, "com.kdwarm.redis.plist")
        XCTAssertEqual(paths.binary("mysqld").lastPathComponent, "mysqld")
        XCTAssertTrue(paths.allDirectories.contains(paths.data))
        XCTAssertTrue(paths.allDirectories.contains(paths.launchAgents))
    }

    // MARK: - LaunchAgentManager plist rendering

    func testLaunchAgentPlistRendersKeyFields() throws {
        let mgr = LaunchAgentManager(paths: paths)
        let spec = LaunchAgentSpec(
            label: "com.kdwarm.redis",
            programArguments: ["/bin/redis-server", "/etc/redis.conf"],
            workingDirectory: "/data/redis",
            stdoutPath: "/logs/redis.log",
            stderrPath: "/logs/redis.log")
        let data = try mgr.plistData(for: spec)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        XCTAssertEqual(plist?["Label"] as? String, "com.kdwarm.redis")
        XCTAssertEqual(plist?["ProgramArguments"] as? [String], ["/bin/redis-server", "/etc/redis.conf"])
        XCTAssertEqual(plist?["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist?["WorkingDirectory"] as? String, "/data/redis")
        // Crash-only restart: a clean bootout (exit 0) must NOT be relaunched.
        let keepAlive = plist?["KeepAlive"] as? [String: Any]
        XCTAssertEqual(keepAlive?["SuccessfulExit"] as? Bool, false)
    }

    func testLaunchAgentGuiDomainUsesCurrentUID() {
        XCTAssertEqual(LaunchAgentManager.guiDomain, "gui/\(getuid())")
    }

    func testParseLoadedLabelsExtractsKDWarmJobsFromServicesBlock() {
        // Mirrors real `launchctl print gui/<uid>` shape: only the services block counts, and only
        // com.kdwarm.* labels are returned (apple jobs + other sections ignored).
        let fixture = """
        gui/501 = {
            services = {
                637      -    com.apple.Finder
                1234     0    com.kdwarm.redis
                1240     0    com.kdwarm.php-fpm.8.4
                0        -    com.kdwarm.nginx
            }
            endpoints = {
                "com.kdwarm.ignored.endpoint" = { active = 1 }
            }
        }
        """
        let labels = LaunchAgentManager.parseLoadedLabels(from: fixture)
        XCTAssertEqual(labels, ["com.kdwarm.redis", "com.kdwarm.php-fpm.8.4", "com.kdwarm.nginx"])
        XCTAssertFalse(labels.contains("com.apple.Finder"))
        XCTAssertFalse(labels.contains("com.kdwarm.ignored.endpoint"))   // outside services block
    }

    // MARK: - RestartPolicy

    func testRestartPolicyStaysStartingThroughLaunchdThrottleThenErrors() {
        // A controllable clock proves the escalation is TIME-based (tolerates launchd's ~10s
        // relaunch throttle) and not probe-count-based.
        var fakeNow = Date(timeIntervalSince1970: 1_000)
        let policy = RestartPolicy(errorAfter: 20, now: { fakeNow })

        XCTAssertEqual(policy.record(.mysql, healthy: false).status, .starting)   // t=0
        fakeNow.addTimeInterval(9)                                                 // mid-throttle
        XCTAssertEqual(policy.record(.mysql, healthy: false).status, .starting)
        fakeNow.addTimeInterval(9)                                                 // t=18, still < 20
        XCTAssertEqual(policy.record(.mysql, healthy: false).status, .starting)
        fakeNow.addTimeInterval(5)                                                 // t=23 ≥ 20 → error
        let exhausted = policy.record(.mysql, healthy: false)
        XCTAssertEqual(exhausted.status, .error)
        XCTAssertTrue(exhausted.exhausted)
    }

    func testRestartPolicyResetsOnHealthyProbe() {
        var fakeNow = Date(timeIntervalSince1970: 1_000)
        let policy = RestartPolicy(errorAfter: 20, now: { fakeNow })
        _ = policy.record(.redis, healthy: false)
        XCTAssertTrue(policy.isFailing(.redis))
        fakeNow.addTimeInterval(30)                       // would be error if still failing
        let ok = policy.record(.redis, healthy: true)     // a healthy probe clears the window
        XCTAssertEqual(ok.status, .running)
        XCTAssertFalse(policy.isFailing(.redis))
    }

    // MARK: - HealthChecker

    func testTCPProbeFailsOnClosedPort() {
        // Port 1 is virtually never listening on a dev mac; a closed port must read false fast.
        XCTAssertFalse(HealthChecker.tcpConnect(host: "127.0.0.1", port: 1, timeout: 0.3))
    }

    func testUnixProbeFailsWhenSocketMissing() {
        XCTAssertFalse(HealthChecker.unixConnect(path: "/tmp/kdwarm-nonexistent-\(UUID()).sock"))
    }

    // MARK: - PortPreflight named conflicts

    func testPreflightNamesDatabaseConflicts() {
        XCTAssertTrue(PortPreflight.conflictMessage(port: 3306, process: "mysqld").contains("MySQL"))
        XCTAssertTrue(PortPreflight.conflictMessage(port: 5432, process: "postgres").contains("PostgreSQL"))
        XCTAssertTrue(PortPreflight.conflictMessage(port: 6379, process: "redis-server").contains("Redis"))
    }

    func testFirstConflictReturnsAvailableForFreePorts() {
        // Two high, almost-certainly-free ports → available (bind test succeeds).
        let outcome = PortPreflight().firstConflict(in: [54_421, 54_422])
        XCTAssertEqual(outcome, .available)
    }

    // MARK: - ServiceInitializer

    func testIsInitializedDetectsMarkerAndEmptiness() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kdwarm-init-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try ServiceInitializer.ensureDir(tmp)
        XCTAssertFalse(ServiceInitializer.isInitialized(tmp))                       // empty
        try Data().write(to: tmp.appendingPathComponent("PG_VERSION"))
        XCTAssertTrue(ServiceInitializer.isInitialized(tmp, marker: "PG_VERSION")) // marker present
        XCTAssertTrue(ServiceInitializer.isInitialized(tmp))                        // non-empty
    }

    // MARK: - BinaryStager optional set

    func testOptionalBinariesIncludeDatabasesAndMailpit() {
        XCTAssertEqual(Set(BinaryStager.optionalBinaryNames),
                       ["mysqld", "postgres", "initdb", "redis-server", "mailpit"])
    }

    // MARK: - Controller installed-state + spec wiring (no launchd)

    func testRedisControllerReportsNotInstalledWithoutBinary() {
        let redis = RedisController(paths: paths, agents: LaunchAgentManager(paths: paths))
        XCTAssertEqual(redis.kind, .redis)
        XCTAssertFalse(redis.isInstalled)            // no staged redis-server in the test tree
        XCTAssertEqual(redis.detail, ":6379")
    }
}
