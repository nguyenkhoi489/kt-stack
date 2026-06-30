import Foundation

// The lifecycle surface the supervisor drives, regardless of engine. Teardown is done by the
// supervisor via launchd label, so a controller only needs start/reload/running.
protocol LoopbackBackendController {
    var isRunning: Bool { get }
    func start() throws
    func reload() throws
}

extension NginxController: LoopbackBackendController {}
extension ApacheController: LoopbackBackendController {}

// Supervises the per-site loopback backend launchd agents (com.ktstack.site.<id>). Config files
// are written by SiteConfigGenerator; this starts/reloads/stops the processes and waits for each
// to actually listen before the front is told to route to it.
//
// Teardown is always by launchd LABEL, never by binary path: every backend shares the same nginx
// binary, so a pgrep-by-path reap would SIGTERM the front and all siblings (cascading outage).
public struct SiteBackendSupervisor: Sendable {
    private let paths: AppSupportPaths
    private let agents: LaunchAgentManager

    public init(paths: AppSupportPaths, agents: LaunchAgentManager) {
        self.paths = paths
        self.agents = agents
    }

    static let labelPrefix = "com.ktstack.site."

    // Only PHP sites run a backend; static/node are served by the front directly.
    static func managed(_ sites: [Site]) -> [Site] {
        sites.filter { $0.type == .php && $0.backendPort != nil }
    }

    private func engine(for site: Site) -> WebServerEngine {
        WebServerBackendFactory.effectiveEngine(site.serverEngine, paths: paths)
    }

    private func label(for site: Site) -> String {
        paths.siteBackendLabel(site.id.uuidString, engine: engine(for: site).rawValue)
    }

    // Launch the engine the site will actually run (apache only if its binary is installed). Must
    // match the config SiteConfigGenerator wrote, which uses the same effectiveEngine resolution.
    private func controller(for site: Site) -> LoopbackBackendController {
        let label = label(for: site)
        let conf = paths.siteBackendConf(site.id.uuidString)
        let errorLog = paths.siteErrorLog(site.domain)
        switch engine(for: site) {
        case .nginx:
            return NginxController(
                paths: paths,
                agents: agents,
                instance: NginxInstance(label: label, confFile: conf, prefix: paths.root, errorLog: errorLog)
            )
        case .apache:
            return ApacheController(paths: paths, agents: agents, label: label, conf: conf, errorLog: errorLog)
        }
    }

    // Bring every managed backend up (start new, reload changed to pick up config), confirm each
    // listens, and boot out backends whose site is gone. Per-site failures are isolated: one
    // backend that won't start only 502s its own host, it must not block the front or its
    // siblings from coming up. Run before the front (re)loads so healthy hosts never route to a
    // not-yet-listening backend.
    public func reconcile(sites: [Site]) async {
        let managed = Self.managed(sites)
        // One launchctl read for the whole pass; per-site isLoadedNow would be N launchctl calls
        // and makes every reconcile (e.g. a site toggle) stutter once there are many sites.
        let loaded = Set(agents.loadedLabels(withPrefix: Self.labelPrefix))
        let desiredLabels = Set(managed.map { label(for: $0) })
        for label in loaded where !desiredLabels.contains(label) {
            tearDown(label: label)
        }

        for site in managed {
            guard let port = site.backendPort else { continue }
            do {
                let ctrl = controller(for: site)
                if loaded.contains(label(for: site)) {
                    try ctrl.reload() // already listening; graceful reload needs no readiness wait
                } else {
                    try ctrl.start()
                    try await Self.waitForListen(port: port)
                }
            } catch {
                NSLog("KTStack: backend for \(site.domain) did not come up: \(error.localizedDescription)")
            }
        }
    }

    public func stopAll() {
        // One pass, no per-label launchctl probe (bootout(label) would print-then-bootout each).
        agents.bootout(matchingPrefix: Self.labelPrefix)
    }

    private func tearDown(label: String) {
        try? agents.bootout(label)
        try? FileManager.default.removeItem(at: paths.launchAgentPlist(label))
    }

    static func waitForListen(port: Int, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if HealthChecker.tcpConnect(host: "127.0.0.1", port: port, timeout: 0.3) { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(
            domain: "KTStack",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Site backend did not start listening on 127.0.0.1:\(port) in time."]
        )
    }
}
