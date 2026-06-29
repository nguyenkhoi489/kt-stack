import Foundation

public final class MySQLController: ManagedService, @unchecked Sendable {
    public let kind = ServiceKind.mysql
    public var detail: String {
        ":3306"
    }

    public var logsURL: URL? {
        paths.serviceLog("mysql")
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
        return catalog.binary(.mysql, "bin/mysqld", version: v)
    }

    private var dataDir: URL {
        guard let v = activeVersionProvider() else { return paths.serviceData("mysql") }
        return paths.serviceData("mysql", version: v)
    }

    private var configFile: URL {
        paths.serviceConfig("mysql", ext: "cnf")
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
            kind: .mysql, label: ServiceKind.mysql.launchdLabel,
            preflightPorts: [3306], probe: .tcp(port: 3306), agents: agents
        )
        if let activeVersion {
            activeVersionProvider = activeVersion
        } else {
            activeVersionProvider = { cat.installedVersions(.mysql).max { $0.compare($1, options: .numeric) == .orderedAscending } }
        }
    }

    public func start() async throws {
        guard let binary else { throw ServiceNotInstalled(.mysql) }
        try writeConfig()
        try initializeIfNeeded(binary: binary)
        try await runner.start(spec: spec(binary: binary))
    }

    public func stop() async throws {
        try runner.stop()
    }

    public func restart() async throws {
        guard let binary else { throw ServiceNotInstalled(.mysql) }
        try await runner.restart(spec: spec(binary: binary))
    }

    public func probe() async -> ServiceStatus {
        isInstalled ? await runner.probe() : .stopped
    }

    private func initializeIfNeeded(binary: URL) throws {
        try ServiceInitializer.ensureDir(dataDir)
        guard !ServiceInitializer.isInitialized(dataDir, marker: "mysql") else { return }
        try ServiceInitializer.run(
            binary,
            ["--defaults-file=\(configFile.path)", "--initialize-insecure"],
            tool: "mysqld"
        )
    }

    private func writeConfig() throws {
        let config = """
        [mysqld]
        port = 3306
        bind-address = 127.0.0.1
        datadir = \(dataDir.path)
        socket = \(paths.serviceSocket("mysql").path)
        log-error = \(paths.serviceLog("mysql").path)
        pid-file = \(paths.run.appendingPathComponent("mysql.pid").path)
        """
        try config.write(to: configFile, atomically: true, encoding: .utf8)
    }

    private func spec(binary: URL) -> LaunchAgentSpec {
        LaunchAgentSpec(
            label: kind.launchdLabel,
            programArguments: [binary.path, "--defaults-file=\(configFile.path)"],
            workingDirectory: dataDir.path,
            stdoutPath: paths.serviceLog("mysql").path,
            stderrPath: paths.serviceLog("mysql").path
        )
    }
}
