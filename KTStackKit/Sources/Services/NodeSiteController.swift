import Foundation

public struct NodeSiteController: Sendable {
    public enum State: String, Equatable, Sendable {
        case running, crashed, stopped, needsRuntime, needsInstall, needsCommand
    }

    public enum Readiness: Equatable, Sendable {
        case ready(version: String)
        case needsRuntime
        case needsCommand
        case needsInstall
    }

    public static let labelPrefix = "com.ktstack.node."
    public static let nodeTools: Set<String> = ["node", "npm", "npx", "yarn", "pnpm"]

    private let paths: AppSupportPaths
    private let agents: LaunchAgentManager
    private let health = HealthChecker()
    private let startTimeout: TimeInterval
    private let installedNodeVersions: @Sendable () -> [String]
    private let nodeModulesPresent: @Sendable (Site) -> Bool

    public init(paths: AppSupportPaths,
                agents: LaunchAgentManager,
                startTimeout: TimeInterval = 12,
                installedNodeVersions: @escaping @Sendable () -> [String],
                nodeModulesPresent: @escaping @Sendable (Site) -> Bool = NodeSiteController.fileSystemNodeModulesCheck) {
        self.paths = paths
        self.agents = agents
        self.startTimeout = startTimeout
        self.installedNodeVersions = installedNodeVersions
        self.nodeModulesPresent = nodeModulesPresent
    }

    public init(paths: AppSupportPaths, agents: LaunchAgentManager, startTimeout: TimeInterval = 12) {
        let catalog = RuntimeCatalog(paths: paths)
        self.init(paths: paths, agents: agents, startTimeout: startTimeout,
                  installedNodeVersions: { catalog.installedVersions(.node) })
    }

    public static func label(domain: String) -> String { labelPrefix + domain }

    public static let fileSystemNodeModulesCheck: @Sendable (Site) -> Bool = { site in
        var isDir: ObjCBool = false
        let modules = URL(fileURLWithPath: site.path).appendingPathComponent("node_modules")
        return FileManager.default.fileExists(atPath: modules.path, isDirectory: &isDir) && isDir.boolValue
    }

    public func readiness(for site: Site) -> Readiness {
        guard let version = resolvedVersion() else { return .needsRuntime }
        let command = site.nodeCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !command.isEmpty else { return .needsCommand }
        guard nodeModulesPresent(site) else { return .needsInstall }
        return .ready(version: version)
    }

    public func buildSpec(for site: Site, version: String) -> LaunchAgentSpec? {
        guard let port = site.nodePort else { return nil }
        let tokens = Self.tokenize(site.nodeCommand ?? "")
        guard !tokens.isEmpty else { return nil }
        let nodeBin = paths.runtimeBin("node", version)
        return LaunchAgentSpec(
            label: Self.label(domain: site.domain),
            programArguments: Self.resolvedProgramArguments(tokens: tokens, nodeBin: nodeBin),
            workingDirectory: site.path,
            environment: Self.environment(port: port, nodeBin: nodeBin),
            stdoutPath: paths.nodeOutLog(site.domain).path,
            stderrPath: paths.nodeErrLog(site.domain).path,
            keepAliveOnCrash: true,
            runAtLoad: true)
    }

    func resolvedVersion() -> String? {
        installedNodeVersions().max { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    static func tokenize(_ command: String) -> [String] {
        command.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }

    static func resolvedProgramArguments(tokens: [String], nodeBin: URL) -> [String] {
        guard let first = tokens.first else { return tokens }
        if first.hasPrefix("/") { return tokens }
        let resolved: String
        if nodeTools.contains(first) {
            resolved = nodeBin.appendingPathComponent(first).path
        } else {
            let candidate = nodeBin.appendingPathComponent(first)
            resolved = FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate.path : first
        }
        return [resolved] + tokens.dropFirst()
    }

    static func environment(port: Int, nodeBin: URL) -> [String: String] {
        ["PORT": String(port),
         "PATH": nodeBin.path + ":/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
         "NODE_ENV": "development"]
    }

    @discardableResult
    public func start(_ site: Site) async throws -> State {
        switch readiness(for: site) {
        case .needsRuntime: return .needsRuntime
        case .needsCommand: return .needsCommand
        case .needsInstall: return .needsInstall
        case .ready(let version):
            guard let spec = buildSpec(for: site, version: version), let port = site.nodePort else {
                return .needsCommand
            }
            if agents.isLoadedNow(spec.label) {
                try agents.writePlist(for: spec)
                try agents.kickstart(spec.label)
            } else {
                try agents.bootstrap(spec)
            }
            return await waitHealthy(port: port) ? .running : .crashed
        }
    }

    public func stop(_ site: Site) {
        try? agents.bootout(Self.label(domain: site.domain))
    }

    public func probe(_ site: Site) async -> State {
        guard let port = site.nodePort else { return .stopped }
        guard agents.isLoaded(Self.label(domain: site.domain)) else { return .stopped }
        return await health.check(.tcp(port: port)) == .running ? .running : .crashed
    }

    public func reconcile(sites: [Site]) async {
        let enabled = sites.filter { $0.type == .node && $0.nodeEnabled && $0.nodePort != nil }
        let desired = Set(enabled.map { Self.label(domain: $0.domain) })
        for label in agents.loadedLabels(withPrefix: Self.labelPrefix) where !desired.contains(label) {
            try? agents.bootout(label)
            try? FileManager.default.removeItem(at: paths.launchAgentPlist(label))
        }
        await withTaskGroup(of: Void.self) { group in
            for site in enabled {
                group.addTask { _ = try? await start(site) }
            }
        }
    }

    public func stopAll() {
        agents.bootout(matchingPrefix: Self.labelPrefix)
    }

    public func installDependencies(_ site: Site) async throws {
        guard let version = resolvedVersion() else {
            throw Self.error("Node runtime is not installed. Download it from Runtimes first.")
        }
        let nodeBin = paths.runtimeBin("node", version)
        let npm = nodeBin.appendingPathComponent("npm")
        let proc = Process()
        proc.executableURL = npm
        proc.arguments = ["install"]
        proc.currentDirectoryURL = URL(fileURLWithPath: site.path)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = nodeBin.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = pipe
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw Self.error("npm install failed (\(proc.terminationStatus)): \(detail)")
        }
    }

    private func waitHealthy(port: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(startTimeout)
        while Date() < deadline {
            if await health.check(.tcp(port: port)) == .running { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    static func error(_ message: String) -> NSError {
        NSError(domain: "KTStack.Node", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

extension NodeSiteController.State {
    public var badgeLabel: String {
        switch self {
        case .running:      return "Running"
        case .crashed:      return "Crashed"
        case .stopped:      return "Stopped"
        case .needsRuntime: return "Needs Node"
        case .needsInstall: return "Needs Install"
        case .needsCommand: return "Needs Command"
        }
    }

    public var isHealthy: Bool { self == .running }

    public var serviceStatus: ServiceStatus {
        switch self {
        case .running:      return .running
        case .crashed:      return .error
        case .stopped:      return .stopped
        case .needsRuntime, .needsInstall, .needsCommand: return .warning
        }
    }
}
