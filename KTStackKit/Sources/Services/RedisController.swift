import Foundation

public final class RedisController: ManagedService, @unchecked Sendable {
    public let kind = ServiceKind.redis
    public var detail: String {
        ":6379"
    }

    public var logsURL: URL? {
        paths.serviceLog("redis")
    }

    public var isInstalled: Bool {
        guard let binary else { return false }
        return FileManager.default.isExecutableFile(atPath: binary.path)
    }

    private let paths: AppSupportPaths
    private let runner: LaunchdServiceRunner
    private let catalog: ServiceBinaryCatalog
    private let activeVersionProvider: () -> String?

    private var binary: URL? {
        guard let v = activeVersionProvider() else { return nil }
        return catalog.binary(.redis, "bin/redis-server", version: v)
    }

    private var dataDir: URL {
        guard let v = activeVersionProvider() else { return paths.serviceData("redis") }
        return paths.serviceData("redis", version: v)
    }

    public init(
        paths: AppSupportPaths,
        agents: LaunchAgentManager,
        activeVersion: (() -> String?)? = nil
    ) {
        self.paths = paths
        let cat = ServiceBinaryCatalog(paths: paths)
        catalog = cat
        runner = LaunchdServiceRunner(
            kind: .redis, label: ServiceKind.redis.launchdLabel,
            preflightPorts: [6379], probe: .tcp(port: 6379), agents: agents
        )
        if let activeVersion {
            activeVersionProvider = activeVersion
        } else {
            activeVersionProvider = { cat.installedVersions(.redis).max { $0.compare($1, options: .numeric) == .orderedAscending } }
        }
    }

    public func start() async throws {
        guard let binary else { throw ServiceNotInstalled(.redis) }
        try ServiceInitializer.ensureDir(dataDir)
        try writeConfig()
        try await runner.start(spec: spec(binary: binary))
    }

    public func stop() async throws {
        try runner.stop()
    }

    public func restart() async throws {
        guard let binary else { throw ServiceNotInstalled(.redis) }
        try await runner.restart(spec: spec(binary: binary))
    }

    public func probe() async -> ServiceStatus {
        isInstalled ? await runner.probe() : .stopped
    }

    private func writeConfig() throws {
        let config = """
        bind 127.0.0.1
        port 6379
        dir "\(dataDir.path)"
        logfile "\(paths.serviceLog("redis").path)"
        daemonize no
        save 900 1
        """
        try config.write(to: paths.serviceConfig("redis"), atomically: true, encoding: .utf8)
    }

    private func spec(binary: URL) -> LaunchAgentSpec {
        LaunchAgentSpec(
            label: kind.launchdLabel,
            programArguments: [binary.path, paths.serviceConfig("redis").path],
            workingDirectory: dataDir.path,
            stdoutPath: paths.serviceLog("redis").path,
            stderrPath: paths.serviceLog("redis").path
        )
    }
}
