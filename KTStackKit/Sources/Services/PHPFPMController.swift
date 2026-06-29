import Foundation

public final class PHPFPMController: @unchecked Sendable {
    public let poolName: String
    private let paths: AppSupportPaths
    private let executable: URL
    private let agents: LaunchAgentManager
    private let poolWriter: PHPFPMPoolWriter

    private var label: String {
        "com.ktstack.php-fpm.\(poolName)"
    }

    public init(
        paths: AppSupportPaths,
        agents: LaunchAgentManager,
        poolName: String = BundledPHP.defaultVersion,
        executable: URL? = nil,
        poolWriter: PHPFPMPoolWriter = PHPFPMPoolWriter()
    ) {
        self.paths = paths
        self.agents = agents
        self.poolName = poolName
        self.executable = executable ?? paths.phpFpmBinary(version: poolName)
        self.poolWriter = poolWriter
    }

    public var isRunning: Bool {
        agents.isLoaded(label)
    }

    public func start() throws {
        let poolConf = try poolWriter.write(paths: paths, poolName: poolName)

        try? PHPIniStore(paths: paths).ensureSeeded(version: poolName)

        if !agents.isLoaded(label) {
            try? FileManager.default.removeItem(at: paths.phpFpmSocket(poolName))
        }
        try agents.bootstrap(spec(poolConf: poolConf))
    }

    public func reload() throws {
        guard agents.isLoaded(label) else { return }
        try agents.kickstart(label)
    }

    public func stop(grace _: TimeInterval = 3.0) {
        try? agents.bootout(label)
        try? FileManager.default.removeItem(at: paths.phpFpmSocket(poolName))
    }

    func spec(poolConf: URL) -> LaunchAgentSpec {
        var args = [executable.path, "-p", paths.root.path, "-y", poolConf.path, "-F"]

        let ini = paths.phpIni(version: poolName)
        if FileManager.default.fileExists(atPath: ini.path) {
            args += ["-c", ini.path]
        }

        return LaunchAgentSpec(
            label: label,
            programArguments: args,
            workingDirectory: paths.root.path,
            environment: ["PHP_INI_SCAN_DIR": paths.phpExtConfDir(version: poolName).path],
            stdoutPath: paths.phpFpmLog(poolName).path,
            stderrPath: paths.phpFpmLog(poolName).path
        )
    }
}
