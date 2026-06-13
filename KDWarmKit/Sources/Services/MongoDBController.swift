import Foundation

/// Supervises an on-demand-installed `mongod` as a user LaunchAgent that persists across app quit.
/// Config is passed entirely via CLI args (no YAML config file — avoids the path-quoting failure
/// class) and the server binds loopback only: a dev-insecure, no-auth, 127.0.0.1-only default,
/// consistent with the MySQL/Redis controllers. Data lives under app-support; mongod runs in the
/// foreground (no `--fork`) so launchd owns the process.
public final class MongoDBController: ManagedService, @unchecked Sendable {
    public let kind = ServiceKind.mongodb
    public var detail: String { ":27017" }
    public var logsURL: URL? { paths.serviceLog("mongodb") }
    /// Derived from the SAME resolved binary `start()` will launch, so a wrong path can't report
    /// "installed" yet fail to start.
    public var isInstalled: Bool {
        guard let binary else { return false }
        return FileManager.default.isExecutableFile(atPath: binary.path)
    }

    private let paths: AppSupportPaths
    private let runner: LaunchdServiceRunner
    private let catalog: ServiceBinaryCatalog
    /// Resolved from the on-demand install location (`runtimes/mongodb/7.0/bin/mongod`).
    private var binary: URL? { catalog.binary(.mongodb, "bin/mongod") }

    public init(paths: AppSupportPaths, agents: LaunchAgentManager) {
        self.paths = paths
        self.catalog = ServiceBinaryCatalog(paths: paths)
        self.runner = LaunchdServiceRunner(
            kind: .mongodb, label: ServiceKind.mongodb.launchdLabel,
            preflightPorts: [27017], probe: .tcp(port: 27017), agents: agents,
            // WiredTiger journal replay on cold start can exceed the default 8s; 15s leaves headroom
            // for a fresh-start boot while still failing fast on a real misconfiguration.
            startTimeout: 15)
    }

    public func start() async throws {
        guard let binary else { throw ServiceNotInstalled(.mongodb) }
        try ServiceInitializer.ensureDir(paths.serviceData("mongodb"))
        try await runner.start(spec: spec(binary: binary))
    }
    public func stop() async throws { try runner.stop() }
    public func restart() async throws {
        guard let binary else { throw ServiceNotInstalled(.mongodb) }
        try await runner.restart(spec: spec(binary: binary))
    }
    public func probe() async -> ServiceStatus { isInstalled ? await runner.probe() : .stopped }

    /// Launch arguments for mongod. Loopback-only bind is a hard security invariant (covered by a
    /// unit test); no auth is enabled this round (service-only scope).
    func mongoArgs(binary: URL) -> [String] {
        [binary.path,
         "--dbpath", paths.serviceData("mongodb").path,
         "--bind_ip", "127.0.0.1",
         "--port", "27017"]
    }

    private func spec(binary: URL) -> LaunchAgentSpec {
        LaunchAgentSpec(
            label: kind.launchdLabel,
            programArguments: mongoArgs(binary: binary),
            workingDirectory: paths.serviceData("mongodb").path,
            stdoutPath: paths.serviceLog("mongodb").path,
            stderrPath: paths.serviceLog("mongodb").path)
    }
}
