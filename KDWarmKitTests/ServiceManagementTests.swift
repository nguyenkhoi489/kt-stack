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
        XCTAssertEqual(ServiceKind.mongodb.defaultPort, 27017)
        XCTAssertEqual(ServiceKind.mongodb.launchdLabel, "com.kdwarm.mongodb")
        XCTAssertEqual(ServiceKind.mongodb.binaryName, "mongod")
        XCTAssertEqual(Set(ServiceKind.allCases).count, 8)
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
            stderrPath: "/logs/redis.log",
            fileDescriptorLimit: 8192)
        let data = try mgr.plistData(for: spec)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        XCTAssertEqual(plist?["Label"] as? String, "com.kdwarm.redis")
        XCTAssertEqual(plist?["ProgramArguments"] as? [String], ["/bin/redis-server", "/etc/redis.conf"])
        XCTAssertEqual(plist?["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist?["WorkingDirectory"] as? String, "/data/redis")
        // Crash-only restart: a clean bootout (exit 0) must NOT be relaunched.
        let keepAlive = plist?["KeepAlive"] as? [String: Any]
        XCTAssertEqual(keepAlive?["SuccessfulExit"] as? Bool, false)
        XCTAssertEqual(plist?["ThrottleInterval"] as? Int, 10)
        let softLimits = plist?["SoftResourceLimits"] as? [String: Any]
        let hardLimits = plist?["HardResourceLimits"] as? [String: Any]
        XCTAssertEqual(softLimits?["NumberOfFiles"] as? Int, 8192)
        XCTAssertEqual(hardLimits?["NumberOfFiles"] as? Int, 8192)
    }

    func testNginxReloadReportsCommandFailure() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kdwarm-nginx-reload-\(UUID().uuidString)", isDirectory: true)
        let p = AppSupportPaths(root: root)
        try p.ensureDirectoryTree()
        let script = p.nginxBinary
        let contents = """
        #!/bin/sh
        echo reload failed >&2
        exit 7
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let nginx = NginxController(paths: p, agents: LaunchAgentManager(paths: p))
        XCTAssertThrowsError(try nginx.reload()) { error in
            XCTAssertTrue(error.localizedDescription.contains("exit code 7"))
            XCTAssertTrue(error.localizedDescription.contains("reload failed"))
        }
    }

    func testStrayProcessReaperExcludesSelfAndUnknownPaths() {
        XCTAssertTrue(StrayProcessReaper.pids(matching: "/no/such/binary-\(UUID().uuidString)").isEmpty)
        let ownExecutable = ProcessInfo.processInfo.arguments[0]
        XCTAssertFalse(StrayProcessReaper.pids(matching: ownExecutable).contains(getpid()))
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

    func testLoopbackListenerIsDetectedByConnectProbeNotWildcardBind() throws {
        let listenFD = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(listenFD, 0)
        defer { close(listenFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(Darwin.listen(listenFD, 1), 0)

        var assigned = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(listenFD, $0, &len)
            }
        }
        let port = Int(UInt16(bigEndian: assigned.sin_port))

        XCTAssertTrue(HealthChecker.tcpConnect(host: "127.0.0.1", port: port, timeout: 0.5),
                      "connect probe must detect a 127.0.0.1-bound listener")
        XCTAssertEqual(PortPreflight().check(port: port), .available,
                       "wildcard bind probe cannot see a loopback-only listener — hence the connect probe")
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

    func testOnlyMailpitIsBundledOptionally() {
        // DB engines install on-demand (ServiceBinaryCatalog), not bundled — only Mailpit ships.
        XCTAssertEqual(Set(BinaryStager.optionalBinaryNames), ["mailpit"])
    }

    // MARK: - Controller installed-state + spec wiring (no launchd)

    func testRedisControllerReportsNotInstalledWithoutBinary() {
        let redis = RedisController(paths: paths, agents: LaunchAgentManager(paths: paths))
        XCTAssertEqual(redis.kind, .redis)
        XCTAssertFalse(redis.isInstalled)            // no on-demand install in the test tree
        XCTAssertEqual(redis.detail, ":6379")
    }

    func testMongoDBControllerReportsNotInstalledWithoutBinary() {
        let mongo = MongoDBController(paths: paths, agents: LaunchAgentManager(paths: paths))
        XCTAssertEqual(mongo.kind, .mongodb)
        XCTAssertFalse(mongo.isInstalled)            // no on-demand install in the test tree
        XCTAssertEqual(mongo.detail, ":27017")
    }

    func testMongoDBControllerIsInstalledOnlyWithBinUnderBinDir() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-mongoctl-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)
        let mongo = MongoDBController(paths: p, agents: LaunchAgentManager(paths: p))
        XCTAssertFalse(mongo.isInstalled)
        let bin = p.runtimeBin("mongodb", "7.0")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bin.appendingPathComponent("mongod").path,
                                       contents: Data(), attributes: [.posixPermissions: 0o755])
        XCTAssertTrue(mongo.isInstalled, "mongod under bin/ must mark the controller installed")
    }

    /// Security invariant: the launch args MUST bind loopback only (dev-insecure, no-auth) and never
    /// expose mongod on all interfaces.
    func testMongoDBSpecBindsLoopback() {
        let mongo = MongoDBController(paths: paths, agents: LaunchAgentManager(paths: paths))
        let args = mongo.mongoArgs(binary: URL(fileURLWithPath: "/x/bin/mongod"))
        XCTAssertTrue(args.contains("--bind_ip"))
        XCTAssertTrue(args.contains("127.0.0.1"))
        XCTAssertFalse(args.contains("0.0.0.0"))
        XCTAssertFalse(args.contains("--bindIpAll"))
        XCTAssertTrue(args.contains("--dbpath"))
        XCTAssertTrue(args.contains("--port"))
        XCTAssertTrue(args.contains("27017"))
    }

    // MARK: - ServiceManager order + reset-data

    @MainActor
    func testServiceManagerOrderIncludesMongoDB() {
        let order = ServiceManager.order
        guard let redisIdx = order.firstIndex(of: .redis),
              let mongoIdx = order.firstIndex(of: .mongodb),
              let mailpitIdx = order.firstIndex(of: .mailpit) else {
            return XCTFail("order missing an expected kind")
        }
        XCTAssertEqual(mongoIdx, redisIdx + 1, "MongoDB must sit right after Redis")
        XCTAssertLessThan(mongoIdx, mailpitIdx, "MongoDB must precede Mailpit")
    }

    func testResetDataRemovesServiceDataDir() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-reset-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppSupportPaths(root: root)
        let dir = paths.serviceData("mongodb")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("mongod.lock"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        ServiceManager.removeServiceData(.mongodb, paths: paths)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path), "reset must delete the data dir")
    }

    // MARK: - ServiceBinaryCatalog (on-demand DB install)

    func testServiceManifestWellFormed() {
        XCTAssertFalse(ServiceBinaryCatalog.manifest.isEmpty)
        for r in ServiceBinaryCatalog.manifest {
            guard r.supportsCurrentArch, !r.sha256.hasPrefix("PENDING_") else { continue }
            XCTAssertEqual(r.sha256.count, 64, "\(r.id) sha256 must be 64 hex chars")
            XCTAssertTrue(r.url.absoluteString.hasPrefix("https://"), "\(r.id) must download over https")
            // Self-built engines follow the `<kind>-<version>-<arch>.tar.gz` name; an engine with a
            // direct-upstream URL (e.g. MongoDB's fastdl tarball) carries its own naming, so the
            // suffix check applies only to the self-host entries.
            if r.urlOverridesByArch[ServiceBinaryCatalog.arch] == nil {
                XCTAssertTrue(r.url.absoluteString.hasSuffix("\(r.kind.rawValue)-\(r.version)-\(ServiceBinaryCatalog.arch).tar.gz"))
            }
        }
    }

    func testCatalogResolvesInstalledEngineAndHidesAvailable() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-svc-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppSupportPaths(root: root)
        let catalog = ServiceBinaryCatalog(paths: paths)

        // Not installed → no binary, but a catalog release is offered.
        XCTAssertFalse(catalog.isInstalled(.redis))
        XCTAssertNil(catalog.binary(.redis, "bin/redis-server"))
        XCTAssertEqual(catalog.availableRelease(.redis)?.version, "7.4.2")

        // Simulate an on-demand install: runtimes/redis/7.4.2/bin/redis-server.
        let bin = paths.runtimeBin("redis", "7.4.2")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bin.appendingPathComponent("redis-server").path,
                                       contents: Data(), attributes: [.posixPermissions: 0o755])

        XCTAssertTrue(catalog.isInstalled(.redis))
        XCTAssertEqual(catalog.installedVersion(.redis), "7.4.2")
        XCTAssertEqual(catalog.binary(.redis, "bin/redis-server")?.lastPathComponent, "redis-server")
        XCTAssertNil(catalog.availableRelease(.redis), "installed engine is not offered for install")
    }

    func testCatalogResolvesInstalledMongoDB() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-mongo-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppSupportPaths(root: root)
        let catalog = ServiceBinaryCatalog(paths: paths)

        // Not installed → no binary, but the direct-fetch catalog release is offered.
        XCTAssertFalse(catalog.isInstalled(.mongodb))
        XCTAssertNil(catalog.binary(.mongodb, "bin/mongod"))
        XCTAssertEqual(catalog.availableRelease(.mongodb)?.version, "7.0")

        // Simulate an on-demand install: runtimes/mongodb/7.0/bin/mongod.
        let bin = paths.runtimeBin("mongodb", "7.0")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bin.appendingPathComponent("mongod").path,
                                       contents: Data(), attributes: [.posixPermissions: 0o755])

        XCTAssertTrue(catalog.isInstalled(.mongodb))
        XCTAssertEqual(catalog.installedVersion(.mongodb), "7.0")
        XCTAssertEqual(catalog.binary(.mongodb, "bin/mongod")?.lastPathComponent, "mongod")
        XCTAssertNil(catalog.availableRelease(.mongodb), "installed engine is not offered for install")
    }

    func testRedisControllerIsInstalledOnlyWithBinUnderBinDir() throws {
        // Locks the binary path: the controller must resolve runtimes/redis/<v>/bin/redis-server.
        // A wrong relPath (missing "bin/") would leave isInstalled false despite the marker existing.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-redisctl-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)
        let redis = RedisController(paths: p, agents: LaunchAgentManager(paths: p))
        XCTAssertFalse(redis.isInstalled)
        let bin = p.runtimeBin("redis", "7.4.2")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bin.appendingPathComponent("redis-server").path,
                                       contents: Data(), attributes: [.posixPermissions: 0o755])
        XCTAssertTrue(redis.isInstalled, "redis-server under bin/ must mark the controller installed")
    }

    func testCatalogOffersMySQLRelease() {
        // MySQL is published + notarized → installable on demand (nothing installed yet, so it shows).
        let catalog = ServiceBinaryCatalog(paths: paths)
        let release = catalog.availableRelease(.mysql)
        XCTAssertNotNil(release)
        XCTAssertEqual(release?.url.host, "github.com")
        XCTAssertEqual(release?.url.lastPathComponent, "mysql-9.6.0-arm64.tar.gz")
        XCTAssertNotNil(ServiceBinaryCatalog.marker(.mysql))
    }
}
