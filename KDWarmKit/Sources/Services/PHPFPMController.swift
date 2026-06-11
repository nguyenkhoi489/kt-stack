import Foundation

/// Starts/stops one php-fpm master + pool as a user LaunchAgent that PERSISTS across app quit.
/// `poolName` doubles as the pool key and socket suffix (`run/php-fpm-<poolName>.sock`);
/// `PHPFPMPoolManager` keys pools by PHP version, so `poolName` is the version (e.g. "8.4") and
/// `executable` the matching versioned binary.
///
/// The master runs foreground (`-F`, `daemonize = no`) under launchd; `KeepAlive` auto-restarts a
/// crash, a clean stop is a `bootout`.
public final class PHPFPMController: @unchecked Sendable {
    public let poolName: String
    private let paths: AppSupportPaths
    private let executable: URL
    private let agents: LaunchAgentManager
    private let poolWriter: PHPFPMPoolWriter

    /// One launchd job per pool: `com.kdwarm.php-fpm.<version>`.
    private var label: String { "com.kdwarm.php-fpm.\(poolName)" }

    public init(paths: AppSupportPaths,
                agents: LaunchAgentManager,
                poolName: String = BundledPHP.defaultVersion,
                executable: URL? = nil,
                poolWriter: PHPFPMPoolWriter = PHPFPMPoolWriter()) {
        self.paths = paths
        self.agents = agents
        self.poolName = poolName
        self.executable = executable ?? paths.phpFpmBinary(version: poolName)
        self.poolWriter = poolWriter
    }

    public var isRunning: Bool { agents.isLoaded(label) }

    /// Render the pool config and bootstrap the launchd job (idempotent reattach if already loaded).
    public func start() throws {
        let poolConf = try poolWriter.write(paths: paths, poolName: poolName)
        // Stale socket from a crash would make nginx see a dead socket — clear it before (re)launch.
        if !agents.isLoaded(label) {
            try? FileManager.default.removeItem(at: paths.phpFpmSocket(poolName))
        }
        try agents.bootstrap(spec(poolConf: poolConf))
    }

    public func stop(grace: TimeInterval = 3.0) {
        try? agents.bootout(label)
        try? FileManager.default.removeItem(at: paths.phpFpmSocket(poolName))
    }

    private func spec(poolConf: URL) -> LaunchAgentSpec {
        LaunchAgentSpec(
            label: label,
            programArguments: [executable.path, "-p", paths.root.path, "-y", poolConf.path, "-F"],
            workingDirectory: paths.root.path,
            stdoutPath: paths.phpFpmLog(poolName).path,
            stderrPath: paths.phpFpmLog(poolName).path)
    }
}
