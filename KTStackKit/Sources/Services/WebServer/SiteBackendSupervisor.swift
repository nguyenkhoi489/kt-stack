import Foundation

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

    private func instance(for site: Site) -> NginxInstance {
        NginxInstance(
            label: paths.siteBackendLabel(site.id.uuidString),
            confFile: paths.siteBackendConf(site.id.uuidString),
            prefix: paths.root,
            errorLog: paths.siteErrorLog(site.domain)
        )
    }

    private func controller(for site: Site) -> NginxController {
        NginxController(paths: paths, agents: agents, instance: instance(for: site))
    }

    // Bring every managed backend up (start new, reload changed to pick up config), confirm each
    // listens, and boot out backends whose site is gone. Must run before the front (re)loads so
    // the front never proxy_passes to a dead loopback port.
    public func reconcile(sites: [Site]) async throws {
        let managed = Self.managed(sites)
        let desiredLabels = Set(managed.map { paths.siteBackendLabel($0.id.uuidString) })
        reapExcept(keeping: desiredLabels)

        for site in managed {
            guard let port = site.backendPort else { continue }
            let ctrl = controller(for: site)
            if agents.isLoadedNow(paths.siteBackendLabel(site.id.uuidString)) {
                try? ctrl.reload()
            } else {
                try ctrl.start()
            }
            try await Self.waitForListen(port: port)
        }
    }

    public func stopAll() {
        for label in agents.loadedLabels(withPrefix: Self.labelPrefix) {
            tearDown(label: label)
        }
    }

    public func stop(site: Site) {
        tearDown(label: paths.siteBackendLabel(site.id.uuidString))
    }

    private func reapExcept(keeping desiredLabels: Set<String>) {
        for label in agents.loadedLabels(withPrefix: Self.labelPrefix) where !desiredLabels.contains(label) {
            tearDown(label: label)
        }
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
