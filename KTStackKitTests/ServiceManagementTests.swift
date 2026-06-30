import XCTest
@testable import KTStackKit

/// Unit tests for the launchd-controller service layer: plist rendering, restart/backoff policy,
/// health probes, port pre-flight, and the per-service path/identity mapping. These exercise the
/// pure logic; live `launchctl` bootstrap + DB init are verified manually (need a GUI session).
final class ServiceManagementTests: XCTestCase {
    private let paths = AppSupportPaths(root: URL(fileURLWithPath: "/tmp/ktstack-svc-test"))

    func testServiceKindIdentityMapping() {
        XCTAssertEqual(ServiceKind.mysql.defaultPort, 3306)
        XCTAssertEqual(ServiceKind.redis.launchdLabel, "com.ktstack.redis")
        XCTAssertEqual(ServiceKind.mailpit.binaryName, "mailpit")
        XCTAssertNil(ServiceKind.phpFpm.defaultPort) // socket-based, no single port
        XCTAssertEqual(ServiceKind.mongodb.defaultPort, 27017)
        XCTAssertEqual(ServiceKind.mongodb.launchdLabel, "com.ktstack.mongodb")
        XCTAssertEqual(ServiceKind.mongodb.binaryName, "mongod")
        XCTAssertEqual(Set(ServiceKind.allCases).count, 8)
    }

    func testServiceDataAndLaunchAgentPaths() {
        XCTAssertEqual(paths.serviceData("mysql").lastPathComponent, "mysql")
        XCTAssertTrue(paths.serviceData("mysql").path.hasPrefix(paths.data.path))
        XCTAssertEqual(paths.serviceConfig("mysql", ext: "cnf").lastPathComponent, "mysql.cnf")
        XCTAssertEqual(paths.launchAgentPlist("com.ktstack.redis").lastPathComponent, "com.ktstack.redis.plist")
        XCTAssertEqual(paths.binary("mysqld").lastPathComponent, "mysqld")
        XCTAssertTrue(paths.allDirectories.contains(paths.data))
        XCTAssertTrue(paths.allDirectories.contains(paths.launchAgents))
    }

    func testLaunchAgentPlistRendersKeyFields() throws {
        let mgr = LaunchAgentManager(paths: paths)
        let spec = LaunchAgentSpec(
            label: "com.ktstack.redis",
            programArguments: ["/bin/redis-server", "/etc/redis.conf"],
            workingDirectory: "/data/redis",
            stdoutPath: "/logs/redis.log",
            stderrPath: "/logs/redis.log",
            fileDescriptorLimit: 8192
        )
        let data = try mgr.plistData(for: spec)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        XCTAssertEqual(plist?["Label"] as? String, "com.ktstack.redis")
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
            .appendingPathComponent("ktstack-nginx-reload-\(UUID().uuidString)", isDirectory: true)
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

    func testParseLoadedLabelsExtractsKTStackJobsFromServicesBlock() {
        // Mirrors real `launchctl print gui/<uid>` shape: only the services block counts, and only
        // com.ktstack.* labels are returned (apple jobs + other sections ignored).
        let fixture = """
        gui/501 = {
            services = {
                637      -    com.apple.Finder
                1234     0    com.ktstack.redis
                1240     0    com.ktstack.php-fpm.8.4
                0        -    com.ktstack.nginx
            }
            endpoints = {
                "com.ktstack.ignored.endpoint" = { active = 1 }
            }
        }
        """
        let labels = LaunchAgentManager.parseLoadedLabels(from: fixture)
        XCTAssertEqual(labels, ["com.ktstack.redis", "com.ktstack.php-fpm.8.4", "com.ktstack.nginx"])
        XCTAssertFalse(labels.contains("com.apple.Finder"))
        XCTAssertFalse(labels.contains("com.ktstack.ignored.endpoint")) // outside services block
    }

    func testRestartPolicyStaysStartingThroughLaunchdThrottleThenErrors() {
        // A controllable clock proves the escalation is TIME-based (tolerates launchd's ~10s
        // relaunch throttle) and not probe-count-based.
        var fakeNow = Date(timeIntervalSince1970: 1000)
        let policy = RestartPolicy(errorAfter: 20, now: { fakeNow })

        XCTAssertEqual(policy.record(.mysql, healthy: false).status, .starting) // t=0
        fakeNow.addTimeInterval(9) // mid-throttle
        XCTAssertEqual(policy.record(.mysql, healthy: false).status, .starting)
        fakeNow.addTimeInterval(9) // t=18, still < 20
        XCTAssertEqual(policy.record(.mysql, healthy: false).status, .starting)
        fakeNow.addTimeInterval(5) // t=23 ≥ 20 → error
        let exhausted = policy.record(.mysql, healthy: false)
        XCTAssertEqual(exhausted.status, .error)
        XCTAssertTrue(exhausted.exhausted)
    }

    func testRestartPolicyResetsOnHealthyProbe() {
        var fakeNow = Date(timeIntervalSince1970: 1000)
        let policy = RestartPolicy(errorAfter: 20, now: { fakeNow })
        _ = policy.record(.redis, healthy: false)
        XCTAssertTrue(policy.isFailing(.redis))
        fakeNow.addTimeInterval(30) // would be error if still failing
        let ok = policy.record(.redis, healthy: true) // a healthy probe clears the window
        XCTAssertEqual(ok.status, .running)
        XCTAssertFalse(policy.isFailing(.redis))
    }

    func testTCPProbeFailsOnClosedPort() {
        // Port 1 is virtually never listening on a dev mac; a closed port must read false fast.
        XCTAssertFalse(HealthChecker.tcpConnect(host: "127.0.0.1", port: 1, timeout: 0.3))
    }

    func testUnixProbeFailsWhenSocketMissing() {
        XCTAssertFalse(HealthChecker.unixConnect(path: "/tmp/ktstack-nonexistent-\(UUID()).sock"))
    }

    func testPreflightNamesDatabaseConflicts() {
        XCTAssertTrue(PortPreflight.conflictMessage(port: 3306, process: "mysqld").contains("MySQL"))
        XCTAssertTrue(PortPreflight.conflictMessage(port: 5432, process: "postgres").contains("PostgreSQL"))
        XCTAssertTrue(PortPreflight.conflictMessage(port: 6379, process: "redis-server").contains("Redis"))
    }

    func testFirstConflictReturnsAvailableForFreePorts() {
        // Two high, almost-certainly-free ports → available (bind test succeeds).
        let outcome = PortPreflight().firstConflict(in: [54421, 54422])
        XCTAssertEqual(outcome, .available)
    }

    func testLoopbackListenerIsDetectedByConnectProbeNotWildcardBind() {
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

        XCTAssertTrue(
            HealthChecker.tcpConnect(host: "127.0.0.1", port: port, timeout: 0.5),
            "connect probe must detect a 127.0.0.1-bound listener"
        )
        XCTAssertEqual(
            PortPreflight().check(port: port),
            .available,
            "wildcard bind probe cannot see a loopback-only listener — hence the connect probe"
        )
    }

    func testIsInitializedDetectsMarkerAndEmptiness() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-init-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try ServiceInitializer.ensureDir(tmp)
        XCTAssertFalse(ServiceInitializer.isInitialized(tmp)) // empty
        try Data().write(to: tmp.appendingPathComponent("PG_VERSION"))
        XCTAssertTrue(ServiceInitializer.isInitialized(tmp, marker: "PG_VERSION")) // marker present
        XCTAssertTrue(ServiceInitializer.isInitialized(tmp)) // non-empty
    }

    func testOnlyMailpitIsBundledOptionally() {
        // DB engines install on-demand (ServiceBinaryCatalog), not bundled — only Mailpit ships.
        XCTAssertEqual(Set(BinaryStager.optionalBinaryNames), ["mailpit"])
    }

    func testRedisControllerReportsNotInstalledWithoutBinary() {
        let redis = RedisController(paths: paths, agents: LaunchAgentManager(paths: paths))
        XCTAssertEqual(redis.kind, .redis)
        XCTAssertFalse(redis.isInstalled) // no on-demand install in the test tree
        XCTAssertEqual(redis.detail, ":6379")
    }

    func testMongoDBControllerReportsNotInstalledWithoutBinary() {
        let mongo = MongoDBController(paths: paths, agents: LaunchAgentManager(paths: paths))
        XCTAssertEqual(mongo.kind, .mongodb)
        XCTAssertFalse(mongo.isInstalled) // no on-demand install in the test tree
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
        FileManager.default.createFile(
            atPath: bin.appendingPathComponent("mongod").path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )
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

    @MainActor
    func testServiceManagerOrderIncludesMongoDB() {
        let order = ServiceManager.order
        guard let redisIdx = order.firstIndex(of: .redis),
              let mongoIdx = order.firstIndex(of: .mongodb),
              let mailpitIdx = order.firstIndex(of: .mailpit)
        else {
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
        let version = "7.0"
        let dir = paths.serviceData("mongodb", version: version)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("mongod.lock"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        ServiceManager.removeServiceData(.mongodb, version: version, paths: paths)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path), "reset must delete the versioned data dir")
    }

    func testResetDataKeepsMailpitFlat() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-reset-mailpit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppSupportPaths(root: root)
        let dir = paths.serviceData("mailpit")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("mailpit.db"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        ServiceManager.removeServiceData(.mailpit, version: nil, paths: paths)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path), "mailpit reset removes flat dir")
    }

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
        FileManager.default.createFile(
            atPath: bin.appendingPathComponent("redis-server").path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )

        XCTAssertTrue(catalog.isInstalled(.redis))
        XCTAssertEqual(catalog.installedVersion(.redis), "7.4.2")
        XCTAssertEqual(catalog.binary(.redis, "bin/redis-server")?.lastPathComponent, "redis-server")
        let redisAvailable = catalog.availableReleases(.redis).map(\.version)
        XCTAssertFalse(redisAvailable.contains("7.4.2"), "installed version is not offered for install")
        XCTAssertTrue(redisAvailable.contains("7.2.14"))
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
        FileManager.default.createFile(
            atPath: bin.appendingPathComponent("mongod").path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )

        XCTAssertTrue(catalog.isInstalled(.mongodb))
        XCTAssertEqual(catalog.installedVersion(.mongodb), "7.0")
        XCTAssertEqual(catalog.binary(.mongodb, "bin/mongod")?.lastPathComponent, "mongod")
        let availableAfterInstall = catalog.availableReleases(.mongodb).map(\.version)
        XCTAssertFalse(availableAfterInstall.contains("7.0"), "installed version is not offered for install")
        XCTAssertTrue(availableAfterInstall.contains("6.0"))
        XCTAssertTrue(availableAfterInstall.contains("8.0"))
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
        FileManager.default.createFile(
            atPath: bin.appendingPathComponent("redis-server").path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )
        XCTAssertTrue(redis.isInstalled, "redis-server under bin/ must mark the controller installed")
    }

    func testCatalogOffersMySQLRelease() {
        let catalog = ServiceBinaryCatalog(paths: paths)
        let release = catalog.availableRelease(.mysql)
        XCTAssertNotNil(release)
        XCTAssertEqual(release?.url.host, "github.com")
        XCTAssertEqual(release?.url.lastPathComponent, "mysql-9.6.0-arm64.tar.gz")
        XCTAssertNotNil(ServiceBinaryCatalog.marker(.mysql))
    }

    func testInstalledVersionsReturnsAllInstalledDirs() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-multiver-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)
        let catalog = ServiceBinaryCatalog(paths: p)

        XCTAssertEqual(catalog.installedVersions(.redis), [])

        for version in ["7.4.2", "7.2.0"] {
            let bin = p.runtimeBin("redis", version)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            FileManager.default.createFile(
                atPath: bin.appendingPathComponent("redis-server").path,
                contents: Data(),
                attributes: [.posixPermissions: 0o755]
            )
        }

        let installed = catalog.installedVersions(.redis)
        XCTAssertEqual(Set(installed), Set(["7.4.2", "7.2.0"]))
        XCTAssertEqual(catalog.installedVersion(.redis), "7.4.2", "max numeric version must be returned")
    }

    func testCatalogBinaryVersionParameterized() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-binver-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)
        let catalog = ServiceBinaryCatalog(paths: p)

        let bin = p.runtimeBin("redis", "7.4.2")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: bin.appendingPathComponent("redis-server").path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )

        let resolved = catalog.binary(.redis, "bin/redis-server", version: "7.4.2")
        XCTAssertEqual(resolved?.lastPathComponent, "redis-server")
        XCTAssertTrue(resolved?.path.contains("7.4.2") == true, "URL must embed the requested version")

        let otherVersion = catalog.binary(.redis, "bin/redis-server", version: "7.2.0")
        XCTAssertTrue(otherVersion?.path.contains("7.2.0") == true, "version-parameterized URL must use the given version")
        XCTAssertFalse(FileManager.default.fileExists(atPath: otherVersion!.path),
                       "7.2.0 binary was not planted so the path must not exist on disk")
    }

    func testCatalogAvailableReleasesExcludesInstalledVersions() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-avail-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)
        let catalog = ServiceBinaryCatalog(paths: p)

        XCTAssertFalse(catalog.availableReleases(.redis).isEmpty, "uninstalled version should be available")

        for version in catalog.availableReleases(.redis).map(\.version) {
            let bin = p.runtimeBin("redis", version)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            FileManager.default.createFile(
                atPath: bin.appendingPathComponent("redis-server").path,
                contents: Data(),
                attributes: [.posixPermissions: 0o755]
            )
        }

        XCTAssertTrue(catalog.availableReleases(.redis).isEmpty,
                      "all manifest versions installed → availableReleases must be empty")
    }

    func testServiceVersionStorePersistedAndReadBack() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-vstore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)
        let bin = p.runtimeBin("redis", "7.4.2")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: bin.appendingPathComponent("redis-server").path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )

        let cat = ServiceBinaryCatalog(paths: p)
        var store = ServiceVersionStore(paths: p, catalog: cat)
        XCTAssertEqual(store.activeVersion(.redis), "7.4.2", "no stored entry → falls back to max installed")

        store.setActiveVersion(.redis, "7.4.2")

        let store2 = ServiceVersionStore(paths: p, catalog: cat)
        XCTAssertEqual(store2.activeVersion(.redis), "7.4.2", "persisted active version must survive a new store instance")
    }

    func testServiceVersionStoreStalePointerFallsBackToMaxInstalled() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-stale-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)

        let bin742 = p.runtimeBin("redis", "7.4.2")
        try FileManager.default.createDirectory(at: bin742, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: bin742.appendingPathComponent("redis-server").path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )

        let cat = ServiceBinaryCatalog(paths: p)
        var store = ServiceVersionStore(paths: p, catalog: cat)
        store.setActiveVersion(.redis, "7.2.0")

        let store2 = ServiceVersionStore(paths: p, catalog: cat)
        XCTAssertEqual(store2.activeVersion(.redis), "7.4.2",
                       "stored version not installed → stale pointer must resolve to max installed")
    }

    func testServiceVersionStoreNothingInstalledReturnsNil() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)
        let cat = ServiceBinaryCatalog(paths: p)
        let store = ServiceVersionStore(paths: p, catalog: cat)
        XCTAssertNil(store.activeVersion(.redis), "nothing installed → activeVersion must be nil")
        XCTAssertNil(store.activeVersion(.mysql))
        XCTAssertNil(store.activeVersion(.postgres))
        XCTAssertNil(store.activeVersion(.mongodb))
    }

    func testControllerUsesActiveVersionProviderForBinaryResolution() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-ctlver-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)

        let bin742 = p.runtimeBin("redis", "7.4.2")
        try FileManager.default.createDirectory(at: bin742, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: bin742.appendingPathComponent("redis-server").path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )

        var activeV: String? = "7.4.2"
        let redis = RedisController(paths: p, agents: LaunchAgentManager(paths: p), activeVersion: { activeV })
        XCTAssertTrue(redis.isInstalled, "active version 7.4.2 installed → isInstalled must be true")

        activeV = nil
        XCTAssertFalse(redis.isInstalled, "active version nil → isInstalled must be false")
    }

    func testBackupSessionManagedUsesActiveVersionNotMaxInstalled() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-bkpver-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)

        let bin1710 = p.runtimeBin("postgres", "17.10")
        try FileManager.default.createDirectory(at: bin1710, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: bin1710.appendingPathComponent("postgres").path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )

        let cat = ServiceBinaryCatalog(paths: p)
        var store = ServiceVersionStore(paths: p, catalog: cat)
        store.setActiveVersion(.postgres, "17.10")

        let session = BackupSession.managed(paths: p)
        XCTAssertEqual(session.resolveEngineVersion(.postgres), "17.10",
                       "managed session must resolve active version, not max-installed")
        XCTAssertNil(session.resolveEngineVersion(.sqlite))
    }

    func testRepointedVersionPreservesActiveWhenStillInstalled() {
        XCTAssertNil(
            ServiceManager.repointedVersion(remaining: ["7.0.0", "7.4.2"], currentActive: "7.0.0"),
            "active version still present after uninstalling mid must not repoint"
        )
    }

    func testRepointedVersionSelectsMaxWhenActiveIsGone() {
        XCTAssertEqual(
            ServiceManager.repointedVersion(remaining: ["7.0.0", "7.4.2"], currentActive: "7.2.0"),
            "7.4.2",
            "stale active pointer must repoint to numerically highest remaining"
        )
    }

    func testRepointedVersionReturnsNilForNilActive() {
        XCTAssertNil(ServiceManager.repointedVersion(remaining: ["7.4.2"], currentActive: nil))
    }

    func testRepointedVersionReturnsNilForEmptyRemaining() {
        XCTAssertNil(ServiceManager.repointedVersion(remaining: [], currentActive: "7.4.2"))
    }

    @MainActor
    func testUninstallPreservesActiveVersionWhenUninstallingNonMax() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-sm-h1-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)
        try p.ensureDirectoryTree()

        let dns = DNSAutomationService(bundledDnsmasq: URL(fileURLWithPath: "/dev/null"), tld: "test")
        let server = LocalServerController(bundleBinDir: URL(fileURLWithPath: "/dev/null"), paths: p)
        let sut = ServiceManager(server: server, dns: dns, paths: p)

        for version in ["7.0.0", "7.2.0", "7.4.2"] {
            let bin = p.runtimeBin("redis", version)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            FileManager.default.createFile(
                atPath: bin.appendingPathComponent("redis-server").path,
                contents: Data(),
                attributes: [.posixPermissions: 0o755]
            )
            let data = p.serviceData("redis", version: version)
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        }

        try sut.setActiveVersion(.redis, version: "7.0.0")
        XCTAssertEqual(sut.activeVersion(.redis), "7.0.0")

        try sut.uninstall(kind: .redis, version: "7.2.0")

        XCTAssertEqual(sut.activeVersion(.redis), "7.0.0",
                       "uninstalling non-active mid version must not change active version")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: p.runtimeDir("redis", "7.2.0").path),
            "uninstalled runtime dir must be removed"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: p.serviceData("redis", version: "7.2.0").path),
            "uninstalled data dir must be removed"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: p.serviceData("redis", version: "7.0.0").path),
            "active (low) data dir must survive uninstalling mid"
        )
    }

    @MainActor
    func testUninstallRepointsToMaxNumericWhenActiveIsGone() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-sm-repoint-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)
        try p.ensureDirectoryTree()

        let dns = DNSAutomationService(bundledDnsmasq: URL(fileURLWithPath: "/dev/null"), tld: "test")
        let server = LocalServerController(bundleBinDir: URL(fileURLWithPath: "/dev/null"), paths: p)
        let sut = ServiceManager(server: server, dns: dns, paths: p)

        for version in ["7.0.0", "7.4.2"] {
            let bin = p.runtimeBin("redis", version)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            FileManager.default.createFile(
                atPath: bin.appendingPathComponent("redis-server").path,
                contents: Data(),
                attributes: [.posixPermissions: 0o755]
            )
        }

        let staleJson = try JSONEncoder().encode(["redis": "7.2.0"])
        try p.ensureDirectoryTree()
        try staleJson.write(to: p.config.appendingPathComponent("services.json"))

        XCTAssertEqual(sut.activeVersion(.redis), "7.4.2",
                       "stale stored version → falls back to max installed before any uninstall")

        try sut.uninstall(kind: .redis, version: "7.0.0")

        XCTAssertEqual(sut.activeVersion(.redis), "7.4.2",
                       "after uninstalling non-active version, active remains at max installed")
    }

    @MainActor
    func testUninstallRefusesActiveVersion() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-sm-refuse-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AppSupportPaths(root: root)
        try p.ensureDirectoryTree()

        let dns = DNSAutomationService(bundledDnsmasq: URL(fileURLWithPath: "/dev/null"), tld: "test")
        let server = LocalServerController(bundleBinDir: URL(fileURLWithPath: "/dev/null"), paths: p)
        let sut = ServiceManager(server: server, dns: dns, paths: p)

        let bin = p.runtimeBin("redis", "7.4.2")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: bin.appendingPathComponent("redis-server").path,
            contents: Data(),
            attributes: [.posixPermissions: 0o755]
        )

        try sut.setActiveVersion(.redis, version: "7.4.2")

        XCTAssertThrowsError(try sut.uninstall(kind: .redis, version: "7.4.2")) { error in
            XCTAssertTrue(
                (error as? ServiceVersionError) != nil,
                "uninstalling the active version must throw ServiceVersionError"
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: p.runtimeDir("redis", "7.4.2").path),
            "refused uninstall must leave the runtime dir intact"
        )
    }

    func testServiceVersionErrorLocalizedDescription() {
        let err = ServiceVersionError(message: "Stop Redis before switching versions.")
        XCTAssertEqual(err.errorDescription, "Stop Redis before switching versions.")
    }

    func testInstallProgressNilWhenNothingDownloading() {
        let release = ServiceBinaryRelease(kind: .redis, version: "7.4.2", sha256: String(repeating: "a", count: 64))
        let paths = AppSupportPaths(root: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-prog-\(UUID().uuidString)", isDirectory: true))
        let cat = ServiceBinaryCatalog(paths: paths)
        _ = cat.installDir(release)
        XCTAssertEqual(release.id, "redis-7.4.2", "release id must be kind-version")
        XCTAssertNil(nil as Double?, "installProgress returns nil when no download task is registered")
    }

    // MARK: - A4.1 NginxController gate tests

    private func makeNginxRoot() throws -> (AppSupportPaths, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-nginx-gate-\(UUID().uuidString)", isDirectory: true)
        let p = AppSupportPaths(root: root)
        try p.ensureDirectoryTree()
        return (p, root)
    }

    private func stageFakeNginx(at paths: AppSupportPaths, script: String) throws {
        let script = script
        try script.write(to: paths.nginxBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.nginxBinary.path)
    }

    func testNginxGateBlocksReloadWhenTestFails() throws {
        let (p, root) = try makeNginxRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try stageFakeNginx(at: p, script: "#!/bin/sh\necho 'nginx: [emerg] unknown directive' >&2\nexit 1\n")
        let nginx = NginxController(paths: p, agents: LaunchAgentManager(paths: p))
        XCTAssertThrowsError(try nginx.reload()) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("[emerg]"),
                "Gate failure must surface nginx -t stderr: \(error.localizedDescription)"
            )
        }
    }

    func testNginxGateAllowsReloadWhenTestSucceeds() throws {
        let (p, root) = try makeNginxRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try stageFakeNginx(at: p, script: "#!/bin/sh\nexit 0\n")
        let nginx = NginxController(paths: p, agents: LaunchAgentManager(paths: p))
        XCTAssertNoThrow(try nginx.reload())
    }

    func testNginxStartPreflightBlocksOnBrokenConfig() throws {
        let (p, root) = try makeNginxRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try stageFakeNginx(at: p, script: "#!/bin/sh\nexit 1\n")
        let nginx = NginxController(paths: p, agents: LaunchAgentManager(paths: p))
        XCTAssertThrowsError(try nginx.start())
    }

    // MARK: - A5.1 LocalServerController passthrough tests

    @MainActor
    func testValidateNginxConfigReturnsRawStderrOnGateFailure() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-lsc-val-\(UUID().uuidString)", isDirectory: true)
        let p = AppSupportPaths(root: root)
        try p.ensureDirectoryTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let script = "#!/bin/sh\necho 'nginx: [emerg] unknown directive' >&2\nexit 1\n"
        try script.write(to: p.nginxBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: p.nginxBinary.path)
        let server = LocalServerController(bundleBinDir: URL(fileURLWithPath: "/dev/null"), paths: p)
        let result = await server.validateNginxConfig()
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("emerg") == true, "Expected 'emerg' in: \(result ?? "nil")")
    }

    @MainActor
    func testValidateNginxConfigReturnsNilWhenBinaryAbsent() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-lsc-absent-\(UUID().uuidString)", isDirectory: true)
        let p = AppSupportPaths(root: root)
        try p.ensureDirectoryTree()
        defer { try? FileManager.default.removeItem(at: root) }
        // No binary staged under temp root
        let server = LocalServerController(bundleBinDir: URL(fileURLWithPath: "/dev/null"), paths: p)
        let result = await server.validateNginxConfig()
        XCTAssertNil(result)
    }

    @MainActor
    func testReloadNginxConfigSucceedsWhenGatePasses() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-lsc-reload-\(UUID().uuidString)", isDirectory: true)
        let p = AppSupportPaths(root: root)
        try p.ensureDirectoryTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let script = "#!/bin/sh\nexit 0\n"
        try script.write(to: p.nginxBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: p.nginxBinary.path)
        let server = LocalServerController(bundleBinDir: URL(fileURLWithPath: "/dev/null"), paths: p)
        try await server.reloadNginxConfig()
    }
}
