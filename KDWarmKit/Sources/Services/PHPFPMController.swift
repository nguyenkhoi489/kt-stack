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
        // Seed the per-version php.ini so `-c` points at a real file (a missing one would make
        // php-fpm error out); a seeding failure just drops `-c` and runs on compiled defaults.
        try? PHPIniStore(paths: paths).ensureSeeded(version: poolName)
        // Stale socket from a crash would make nginx see a dead socket — clear it before (re)launch.
        if !agents.isLoaded(label) {
            try? FileManager.default.removeItem(at: paths.phpFpmSocket(poolName))
        }
        try agents.bootstrap(spec(poolConf: poolConf))
    }

    /// Restart the loaded master in place so it re-reads its `php.ini` (the editor's Save). No-op if
    /// the pool isn't running — the edit is picked up on the next start since `-c` reads the file fresh.
    public func reload() throws {
        guard agents.isLoaded(label) else { return }
        try agents.kickstart(label)
    }

    public func stop(grace: TimeInterval = 3.0) {
        try? agents.bootout(label)
        try? FileManager.default.removeItem(at: paths.phpFpmSocket(poolName))
    }

    func spec(poolConf: URL) -> LaunchAgentSpec {
        var args = [executable.path, "-p", paths.root.path, "-y", poolConf.path, "-F"]
        // Point php-fpm at the managed per-version php.ini, but only if it exists — `-c` on a missing
        // file makes php-fpm fail to start, so a failed seed safely degrades to compiled defaults.
        let ini = paths.phpIni(version: poolName)
        if FileManager.default.fileExists(atPath: ini.path) {
            args += ["-c", ini.path]
        }
        // Load optional extensions: PHP_INI_SCAN_DIR makes php-fpm parse runtimes/php/<v>/conf.d/*.ini
        // (the extension_dir + per-extension inis the installer writes). It overrides the compiled
        // scan dir and coexists with the `-c` php.ini above (scan-dir inis are parsed in addition).
        return LaunchAgentSpec(
            label: label,
            programArguments: args,
            workingDirectory: paths.root.path,
            environment: ["PHP_INI_SCAN_DIR": paths.phpExtConfDir(version: poolName).path],
            stdoutPath: paths.phpFpmLog(poolName).path,
            stderrPath: paths.phpFpmLog(poolName).path)
    }
}
