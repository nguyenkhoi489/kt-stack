import Foundation

/// Shared start/stop/restart/probe lifecycle for any launchd-backed service (databases, Mailpit,
/// and — after this phase — nginx/php-fpm). Keeps the per-service controllers thin: they only
/// supply first-run init + the rendered `LaunchAgentSpec`; this runner owns the launchd choreography
/// (preflight → bootstrap/kickstart → wait-healthy) and the idempotent reattach path.
public struct LaunchdServiceRunner: Sendable {
    public let kind: ServiceKind
    public let label: String
    /// Ports to pre-flight before a *fresh* start (skipped when reattaching to our own job).
    public let preflightPorts: [Int]
    public let probe: HealthProbe
    /// How long `start()` waits for the first healthy probe before surfacing a warning. Defaults to
    /// 8s (sub-second for most engines); a heavier cold-start (e.g. mongod's WiredTiger journal
    /// replay) passes a wider budget so a slow-but-fine boot isn't misreported as a failure.
    public let startTimeout: TimeInterval

    private let agents: LaunchAgentManager
    private let health = HealthChecker()
    private let preflight = PortPreflight()

    public init(kind: ServiceKind, label: String, preflightPorts: [Int],
                probe: HealthProbe, agents: LaunchAgentManager, startTimeout: TimeInterval = 8) {
        self.kind = kind
        self.label = label
        self.preflightPorts = preflightPorts
        self.probe = probe
        self.agents = agents
        self.startTimeout = startTimeout
    }

    /// Idempotent start. If the job is already loaded we reattach (kickstart only when unhealthy);
    /// otherwise pre-flight the ports, then bootstrap. Returns once the probe reports healthy or the
    /// wait times out (the caller surfaces the timeout as a warning/error via the health poll).
    public func start(spec: LaunchAgentSpec) async throws {
        try verifyBinarySignature(spec)
        if agents.isLoaded(label) {
            if await isHealthy() { return }          // already up — pure reattach
            try agents.kickstart(label)              // loaded but dead → restart in place
        } else {
            switch preflight.firstConflict(in: preflightPorts) {
            case .available: break
            case .inUse(_, let m), .blocked(let m): throw Self.error(m)
            }
            try agents.bootstrap(spec)
        }
        try await waitHealthy(timeout: startTimeout)
    }

    /// Graceful stop: boot the job out of launchd so `KeepAlive` won't relaunch it.
    public func stop() throws { try agents.bootout(label) }

    /// Explicit restart: ensure the plist is current, then kickstart (or bootstrap if not loaded).
    public func restart(spec: LaunchAgentSpec) async throws {
        try verifyBinarySignature(spec)
        try agents.writePlist(for: spec)
        if agents.isLoaded(label) { try agents.kickstart(label) }
        else { try agents.bootstrap(spec) }
        try await waitHealthy(timeout: startTimeout)
    }

    public func probe() async -> ServiceStatus { await health.check(probe) }

    /// Refuse to (re)launch a job whose executable fails a strict code-signature check. On-demand
    /// engines are checksum-verified at install but then lose `com.apple.quarantine` and live in a
    /// user-writable dir, so post-install tampering would otherwise exec with no Gatekeeper prompt.
    /// Re-verifying the binary at launch closes that gap. Ad-hoc-but-valid signatures pass; only an
    /// unsigned or tampered binary fails.
    private func verifyBinarySignature(_ spec: LaunchAgentSpec) throws {
        guard let path = spec.programArguments.first else { return }
        guard BinaryStager.verifySignature(at: URL(fileURLWithPath: path)) else {
            throw Self.error("\(kind.displayName) could not start: its program failed a code-signature "
                + "check. The installed engine may be corrupt — reinstall it.")
        }
    }

    private func isHealthy() async -> Bool { await health.check(probe) == .running }

    private func waitHealthy(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isHealthy() { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        // Not fatal: the service may still be coming up. The poll loop keeps watching; surface a
        // warning so the row doesn't claim "running" prematurely.
        throw Self.error("\(kind.displayName) did not become reachable within \(Int(timeout))s.")
    }

    static func error(_ message: String) -> NSError {
        NSError(domain: "KDWarm.Service", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
