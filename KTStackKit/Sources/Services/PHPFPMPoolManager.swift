import Foundation

public final class PHPFPMPoolManager: @unchecked Sendable {
    private let paths: AppSupportPaths
    private let agents: LaunchAgentManager
    private let lock = NSLock()
    private var pools: [String: PHPFPMController] = [:]

    public init(paths: AppSupportPaths, agents: LaunchAgentManager) {
        self.paths = paths
        self.agents = agents
    }

    public func socket(for version: String) -> URL {
        paths.phpFpmSocket(version)
    }

    public var activeVersions: [String] {
        lock.lock(); defer { lock.unlock() }
        return pools.keys.sorted()
    }

    public func isRunning(version: String) -> Bool {
        lock.lock(); let ctl = pools[version]; lock.unlock()
        return ctl?.isRunning ?? false
    }

    @discardableResult
    public func reconcile(required: Set<String>) throws -> [String] {
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

    public func reload(version: String) throws {
        guard let ctl = pool(for: version) else { return }
        try ctl.reload()
    }

    public func restart(version: String) throws {
        guard let ctl = pool(for: version) else { return }
        ctl.stop()
        try ctl.start()
    }

    public func stopAll(grace: TimeInterval = 3.0) {
        for (_, ctl) in snapshot() {
            ctl.stop(grace: grace)
        }
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
