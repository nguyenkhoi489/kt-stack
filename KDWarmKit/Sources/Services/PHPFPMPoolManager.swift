import Foundation

/// Manages one php-fpm pool per ACTIVE PHP version (not per site) — the core of socket-per-pool
/// isolation. Sites sharing a version share a pool + socket; a version with no sites has no pool.
///
/// Only versions whose binary is installed can start. PHP installs on demand (nothing is bundled),
/// so `reconcile` returns the versions it could not start (missing binary) and the orchestrator warns
/// without aborting the others — those sites serve once the user downloads that version.
public final class PHPFPMPoolManager: @unchecked Sendable {
    private let paths: AppSupportPaths
    private let agents: LaunchAgentManager
    private let lock = NSLock()
    private var pools: [String: PHPFPMController] = [:]

    public init(paths: AppSupportPaths, agents: LaunchAgentManager) {
        self.paths = paths
        self.agents = agents
    }

    public func socket(for version: String) -> URL { paths.phpFpmSocket(version) }

    public var activeVersions: [String] {
        lock.lock(); defer { lock.unlock() }
        return pools.keys.sorted()
    }

    public func isRunning(version: String) -> Bool {
        lock.lock(); let ctl = pools[version]; lock.unlock()
        return ctl?.isRunning ?? false
    }

    /// Bring the running pool set in line with `required`: stop pools no longer needed, start
    /// pools for newly-required versions whose binary exists. Returns versions that were required
    /// but could NOT start because their binary isn't installed (the user hasn't downloaded it yet).
    @discardableResult
    public func reconcile(required: Set<String>) throws -> [String] {
        // Stop + drop pools that are no longer required.
        for (version, ctl) in snapshot() where !required.contains(version) {
            ctl.stop()
            lock.lock(); pools[version] = nil; lock.unlock()
        }

        var missing: [String] = []
        for version in required.sorted() where pool(for: version) == nil {
            let binary = BundledPHP.fpmBinary(for: version, php: paths.phpRuntimesRoot)
            guard FileManager.default.isExecutableFile(atPath: binary.path) else {
                missing.append(version); continue
            }
            let ctl = PHPFPMController(paths: paths, agents: agents, poolName: version, executable: binary)
            try ctl.start()
            lock.lock(); pools[version] = ctl; lock.unlock()
        }
        return missing
    }

    /// Restart one version's running pool in place so it re-reads its edited `php.ini`. No-op if that
    /// version has no live pool (the edit applies on the next start).
    public func reload(version: String) throws {
        guard let ctl = pool(for: version) else { return }
        try ctl.reload()
    }

    public func stopAll(grace: TimeInterval = 3.0) {
        for (_, ctl) in snapshot() { ctl.stop(grace: grace) }
        lock.lock(); pools.removeAll(); lock.unlock()
    }

    private func pool(for version: String) -> PHPFPMController? {
        lock.lock(); defer { lock.unlock() }
        return pools[version]
    }
    private func snapshot() -> [(String, PHPFPMController)] {
        lock.lock(); defer { lock.unlock() }
        return pools.map { ($0.key, $0.value) }
    }
}
