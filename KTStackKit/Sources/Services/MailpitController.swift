import Foundation

public final class MailpitController: ManagedService, @unchecked Sendable {
    public let kind = ServiceKind.mailpit
    public var detail: String {
        ":8025"
    }

    public var logsURL: URL? {
        paths.serviceLog("mailpit")
    }

    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: binary.path)
    }

    public static let uiURL = URL(string: "http://127.0.0.1:8025/")!

    public static let apiBaseURL = URL(string: "http://127.0.0.1:8025/api/v1")!

    private let paths: AppSupportPaths
    private let runner: LaunchdServiceRunner
    private var binary: URL {
        paths.binary("mailpit")
    }

    public init(paths: AppSupportPaths, agents: LaunchAgentManager) {
        self.paths = paths
        runner = LaunchdServiceRunner(
            kind: .mailpit, label: ServiceKind.mailpit.launchdLabel,
            preflightPorts: [8025, 1025], probe: .http(Self.uiURL), agents: agents
        )
    }

    public func start() async throws {
        guard isInstalled else { throw ServiceNotInstalled(.mailpit) }
        try ServiceInitializer.ensureDir(paths.serviceData("mailpit"))
        try await runner.start(spec: spec())
    }

    public func stop() async throws {
        try runner.stop()
    }

    public func restart() async throws {
        guard isInstalled else { throw ServiceNotInstalled(.mailpit) }
        try await runner.restart(spec: spec())
    }

    public func probe() async -> ServiceStatus {
        isInstalled ? await runner.probe() : .stopped
    }

    private func spec() -> LaunchAgentSpec {
        let db = paths.serviceData("mailpit").appendingPathComponent("mailpit.db").path
        return LaunchAgentSpec(
            label: kind.launchdLabel,
            programArguments: [
                binary.path,
                "--database", db,
                "--listen", "127.0.0.1:8025",
                "--smtp", "127.0.0.1:1025",
            ],
            workingDirectory: paths.serviceData("mailpit").path,
            stdoutPath: paths.serviceLog("mailpit").path,
            stderrPath: paths.serviceLog("mailpit").path
        )
    }
}
