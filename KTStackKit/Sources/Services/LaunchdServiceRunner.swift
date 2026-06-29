import Foundation

public struct LaunchdServiceRunner: Sendable {
    public let kind: ServiceKind
    public let label: String

    public let preflightPorts: [Int]
    public let probe: HealthProbe

    public let startTimeout: TimeInterval

    private let agents: LaunchAgentManager
    private let health = HealthChecker()
    private let preflight = PortPreflight()

    public init(
        kind: ServiceKind,
        label: String,
        preflightPorts: [Int],
        probe: HealthProbe,
        agents: LaunchAgentManager,
        startTimeout: TimeInterval = 8
    ) {
        self.kind = kind
        self.label = label
        self.preflightPorts = preflightPorts
        self.probe = probe
        self.agents = agents
        self.startTimeout = startTimeout
    }

    public func start(spec: LaunchAgentSpec) async throws {
        try verifyBinarySignature(spec)
        if agents.isLoaded(label), await isHealthy() { return }
        reapStrayInstances(spec)
        if agents.isLoaded(label) {
            try agents.kickstart(label)
        } else {
            switch preflight.firstConflict(in: preflightPorts) {
            case .available: break
            case let .inUse(_, m), let .blocked(m): throw Self.error(m)
            }
            try agents.bootstrap(spec)
        }
        try await waitHealthy(timeout: startTimeout)
    }

    public func stop() throws {
        try agents.bootout(label)
    }

    public func restart(spec: LaunchAgentSpec) async throws {
        try verifyBinarySignature(spec)
        try agents.writePlist(for: spec)
        if agents.isLoaded(label) { try agents.kickstart(label) }
        else { try agents.bootstrap(spec) }
        try await waitHealthy(timeout: startTimeout)
    }

    public func probe() async -> ServiceStatus {
        await health.check(probe)
    }

    private func reapStrayInstances(_ spec: LaunchAgentSpec) {
        guard let program = spec.programArguments.first else { return }
        StrayProcessReaper.terminate(StrayProcessReaper.pids(matching: program))
    }

    private func verifyBinarySignature(_ spec: LaunchAgentSpec) throws {
        guard let path = spec.programArguments.first else { return }
        guard BinaryStager.verifySignature(at: URL(fileURLWithPath: path)) else {
            throw Self.error(
                "\(kind.displayName) could not start: its program failed a code-signature "
                    + "check. The installed engine may be corrupt — reinstall it."
            )
        }
    }

    private func isHealthy() async -> Bool {
        await health.check(probe) == .running
    }

    private func waitHealthy(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isHealthy() { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        throw Self.error("\(kind.displayName) did not become reachable within \(Int(timeout))s.")
    }

    static func error(_ message: String) -> NSError {
        NSError(domain: "KTStack.Service", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
