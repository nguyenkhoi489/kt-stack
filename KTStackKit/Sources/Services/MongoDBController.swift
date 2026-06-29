import Foundation

public final class MongoDBController: ManagedService, @unchecked Sendable {
    public let kind = ServiceKind.mongodb
    public var detail: String {
        ":27017"
    }

    public var logsURL: URL? {
        paths.serviceLog("mongodb")
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
        return catalog.binary(.mongodb, "bin/mongod", version: v)
    }

    private var dataDir: URL {
        guard let v = activeVersionProvider() else { return paths.serviceData("mongodb") }
        return paths.serviceData("mongodb", version: v)
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
            kind: .mongodb, label: ServiceKind.mongodb.launchdLabel,
            preflightPorts: [27017], probe: .tcp(port: 27017), agents: agents,
            // WiredTiger journal replay on cold start can exceed the default 8s; 15s leaves headroom
            // for a fresh-start boot while still failing fast on a real misconfiguration.
            startTimeout: 15
        )
        if let activeVersion {
            activeVersionProvider = activeVersion
        } else {
            activeVersionProvider = { cat.installedVersions(.mongodb).max { $0.compare($1, options: .numeric) == .orderedAscending } }
        }
    }

    public func start() async throws {
        guard let binary else { throw ServiceNotInstalled(.mongodb) }
        try ServiceInitializer.ensureDir(dataDir)
        try await runner.start(spec: spec(binary: binary))
    }

    public func stop() async throws {
        try runner.stop()
    }

    public func restart() async throws {
        guard let binary else { throw ServiceNotInstalled(.mongodb) }
        try await runner.restart(spec: spec(binary: binary))
    }

    public func probe() async -> ServiceStatus {
        isInstalled ? await runner.probe() : .stopped
    }

    func mongoArgs(binary: URL) -> [String] {
        [
            binary.path,
            "--dbpath",
            dataDir.path,
            "--bind_ip",
            "127.0.0.1",
            "--port",
            "27017",
        ]
    }

    private func spec(binary: URL) -> LaunchAgentSpec {
        LaunchAgentSpec(
            label: kind.launchdLabel,
            programArguments: mongoArgs(binary: binary),
            workingDirectory: dataDir.path,
            stdoutPath: paths.serviceLog("mongodb").path,
            stderrPath: paths.serviceLog("mongodb").path
        )
    }
}
