import Foundation

public final class PostgreSQLController: ManagedService, @unchecked Sendable {
    public let kind = ServiceKind.postgres
    public var detail: String {
        ":5432"
    }

    public var logsURL: URL? {
        paths.serviceLog("postgres")
    }

    public var isInstalled: Bool {
        guard let initdb else { return false }
        return FileManager.default.isExecutableFile(atPath: initdb.path)
    }

    private let paths: AppSupportPaths
    private let runner: LaunchdServiceRunner
    private let catalog: ServiceBinaryCatalog
    private let activeVersionProvider: () -> String?

    private var binary: URL? {
        guard let v = activeVersionProvider() else { return nil }
        return catalog.binary(.postgres, "bin/postgres", version: v)
    }

    private var initdb: URL? {
        guard let v = activeVersionProvider() else { return nil }
        return catalog.binary(.postgres, "bin/initdb", version: v)
    }

    private var dataDir: URL {
        guard let v = activeVersionProvider() else { return paths.serviceData("postgres") }
        return paths.serviceData("postgres", version: v)
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
            kind: .postgres, label: ServiceKind.postgres.launchdLabel,
            preflightPorts: [5432], probe: .tcp(port: 5432), agents: agents
        )
        if let activeVersion {
            activeVersionProvider = activeVersion
        } else {
            activeVersionProvider = { cat.installedVersions(.postgres).max { $0.compare($1, options: .numeric) == .orderedAscending } }
        }
    }

    public func start() async throws {
        guard let binary, let initdb else { throw ServiceNotInstalled(.postgres) }
        try initializeIfNeeded(initdb: initdb)
        try await runner.start(spec: spec(binary: binary))
    }

    public func stop() async throws {
        try runner.stop()
    }

    public func restart() async throws {
        guard let binary else { throw ServiceNotInstalled(.postgres) }
        try await runner.restart(spec: spec(binary: binary))
    }

    public func probe() async -> ServiceStatus {
        isInstalled ? await runner.probe() : .stopped
    }

    private func initializeIfNeeded(initdb: URL) throws {
        try ServiceInitializer.ensureDir(dataDir)
        guard !ServiceInitializer.isInitialized(dataDir, marker: "PG_VERSION") else { return }
        try ServiceInitializer.run(
            initdb,
            ["-D", dataDir.path, "-U", "postgres", "--auth=trust", "--encoding=UTF8"],
            tool: "initdb"
        )
    }

    private func spec(binary: URL) -> LaunchAgentSpec {
        LaunchAgentSpec(
            label: kind.launchdLabel,
            programArguments: [
                binary.path,
                "-D", dataDir.path,
                "-p", "5432",
                "-k", paths.run.path,
                "-c", "listen_addresses=127.0.0.1",
                "-c", "logging_collector=off",
            ],
            workingDirectory: dataDir.path,
            stdoutPath: paths.serviceLog("postgres").path,
            stderrPath: paths.serviceLog("postgres").path
        )
    }
}
