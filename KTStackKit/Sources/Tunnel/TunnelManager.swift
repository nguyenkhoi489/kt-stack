import Foundation
import Combine

@MainActor
public final class TunnelManager: ObservableObject {
    private enum PreparationError: LocalizedError {
        case originPortNotListening(Int)
        case nginxRecoveryFailed(Int, String)

        var errorDescription: String? {
            switch self {
            case .originPortNotListening(let port):
                return "Nginx did not start listening on tunnel origin port \(port). Restart local services and try sharing again."
            case .nginxRecoveryFailed(let port, let message):
                return "Nginx could not activate tunnel origin port \(port): \(message)"
            }
        }
    }

    @Published public private(set) var sessions: [UUID: TunnelSession] = [:]

    public var ttl: TimeInterval = 30 * 60

    private let paths: AppSupportPaths
    private let provisioner: CloudflaredBinaryProvisioner
    private let generator: SiteConfigGenerator
    private let tunnelWriter = NginxTunnelVhostWriter()
    private let preflight = PortPreflight()
    private let nginx: NginxController
    private var controllers: [UUID: TunnelController] = [:]
    private var startTasks: [UUID: Task<Void, Never>] = [:]
    private var ttlTasks: [UUID: Task<Void, Never>] = [:]

    public init(paths: AppSupportPaths = AppSupportPaths()) {
        self.paths = paths
        self.provisioner = CloudflaredBinaryProvisioner(paths: paths)
        self.generator = SiteConfigGenerator(paths: paths)
        self.nginx = NginxController(paths: paths, agents: LaunchAgentManager(paths: paths))
    }

    public func isSharing(_ siteID: UUID) -> Bool {
        sessions[siteID]?.status.isBusy ?? false
    }

    public func session(_ siteID: UUID) -> TunnelSession? { sessions[siteID] }

    public func start(site: Site) {
        guard !isSharing(site.id), startTasks[site.id] == nil else { return }
        tearDown(site.id)
        sessions[site.id] = TunnelSession(siteID: site.id, domain: site.domain,
                                          secure: site.secure, status: .starting)
        let siteID = site.id
        startTasks[siteID] = Task { [weak self] in
            await self?.runStart(site: site)
        }
        scheduleTTL(siteID)
    }

    public func stop(site siteID: UUID) {
        tearDown(siteID)
        sessions[siteID] = nil
    }

    public func reapStaleJobs() {
        LaunchAgentManager(paths: paths).bootout(matchingPrefix: "com.ktstack.tunnel.")
        removeAllTunnelVhosts()
    }

    public func reconcile(sites: [Site]) {
        let live = Dictionary(sites.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (siteID, session) in sessions {
            guard let site = live[siteID],
                  site.domain == session.domain, site.secure == session.secure else {
                stop(site: siteID)
                continue
            }
        }
    }

    public func shutdownAll() {
        for siteID in Set(controllers.keys).union(startTasks.keys).union(ttlTasks.keys) {
            tearDown(siteID)
        }
        sessions.removeAll()
        let provisioner = self.provisioner
        Task { await provisioner.cancel() }
    }

    private func tearDown(_ siteID: UUID) {
        startTasks[siteID]?.cancel()
        startTasks[siteID] = nil
        ttlTasks[siteID]?.cancel()
        ttlTasks[siteID] = nil
        if let controller = controllers.removeValue(forKey: siteID) {
            Task { await controller.stop() }
        }
        removeTunnelVhost(siteID)
    }

    private func scheduleTTL(_ siteID: UUID) {
        guard ttl > 0 else { return }
        let seconds = ttl
        ttlTasks[siteID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            self?.expire(siteID)
        }
    }

    private func expire(_ siteID: UUID) {
        guard isSharing(siteID) else { return }
        tearDown(siteID)
        updateStatus(siteID, .expired)
    }

    private func runStart(site: Site) async {
        let siteID = site.id
        if Task.isCancelled { clearStart(siteID); return }
        if case .available = preflight.check(port: 80) {
            finishStart(siteID, status: .error("Local server isn't running — start KTStack's services first."))
            return
        }
        do {
            if Task.isCancelled { clearStart(siteID); return }
            let originPort = try await prepareTunnelVhost(for: site)
            if Task.isCancelled { clearStart(siteID); return }
            let binary = try await provisioner.ensureInstalled { _ in }
            if Task.isCancelled { clearStart(siteID); return }
            let controller = TunnelController(paths: paths, siteID: siteID)
            controllers[siteID] = controller
            await controller.start(binary: binary, originPort: originPort, localDomain: site.domain,
                onURL: { [weak self] url in
                    guard let host = url.host else { return }
                    await MainActor.run { [weak self] in
                        self?.applyPublicHost(site: site, port: originPort, publicHost: host)
                    }
                },
                onStatus: { [weak self] status in
                    Task { @MainActor [weak self] in
                        self?.updateStatus(siteID, status)
                    }
                })
            startTasks[siteID] = nil
        } catch is CancellationError {
            clearStart(siteID)
        } catch {
            finishStart(siteID, status: .error(error.localizedDescription))
        }
    }

    private func updateStatus(_ siteID: UUID, _ status: TunnelStatus) {
        guard var session = sessions[siteID] else { return }
        session.status = status
        sessions[siteID] = session
    }

    private func finishStart(_ siteID: UUID, status: TunnelStatus) {
        updateStatus(siteID, status)
        startTasks[siteID] = nil
    }

    private func clearStart(_ siteID: UUID) {
        tearDown(siteID)
        sessions[siteID] = nil
    }

    private func prepareTunnelVhost(for site: Site) async throws -> Int {
        let port = selectTunnelPort(site.id)
        try writeTunnelVhost(site: site, port: port, publicHost: nil)
        try await activateTunnelVhost(port: port)
        return port
    }

    private func writeTunnelVhost(site: Site, port: Int, publicHost: String?) throws {
        let socket = site.type == .php ? paths.phpFpmSocket(generator.effectivePHPVersion(site.phpVersion)) : nil
        let config = tunnelWriter.vhost(site: site, port: port, phpFpmSocket: socket,
                                        accessLog: paths.siteAccessLog(site.domain),
                                        errorLog: paths.siteErrorLog(site.domain),
                                        publicHost: publicHost,
                                        supportsBodyRewrite: nginx.supportsResponseBodyRewrite())
        try config.write(to: tunnelVhostURL(site.id), atomically: true, encoding: .utf8)
    }

    private func applyPublicHost(site: Site, port: Int, publicHost: String) {
        guard sessions[site.id]?.status.isBusy == true else { return }
        guard FileManager.default.fileExists(atPath: tunnelVhostURL(site.id).path) else { return }
        guard (try? writeTunnelVhost(site: site, port: port, publicHost: publicHost)) != nil else { return }
        Task { await reloadNginxTolerant() }
    }

    private func activateTunnelVhost(port: Int) async throws {
        if await reloadNginxTolerant(), await waitForTunnelPort(port) { return }
        try await restartNginxForTunnelPort(port, originalError: PreparationError.originPortNotListening(port))
    }

    @discardableResult
    private func reloadNginxTolerant() async -> Bool {
        for attempt in 0..<3 {
            do {
                try nginx.reload()
                return true
            } catch {
                if attempt == 2 { return false }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        return false
    }

    private func restartNginxForTunnelPort(_ port: Int, originalError: Error) async throws {
        do {
            try nginx.restart()
            if await waitForTunnelPort(port) { return }
            throw PreparationError.originPortNotListening(port)
        } catch {
            let message = [originalError.localizedDescription, error.localizedDescription]
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
            throw PreparationError.nginxRecoveryFailed(port, message)
        }
    }

    private func waitForTunnelPort(_ port: Int) async -> Bool {
        for _ in 0..<20 {
            if HealthChecker.tcpConnect(host: "127.0.0.1", port: port, timeout: 0.3) { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private func removeTunnelVhost(_ siteID: UUID) {
        let url = tunnelVhostURL(siteID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
        Task { await reloadNginxTolerant() }
    }

    private func tunnelVhostURL(_ siteID: UUID) -> URL {
        paths.vhost("tunnel-\(siteID.uuidString)")
    }

    private func removeAllTunnelVhosts() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: paths.sitesEnabled,
                                                                       includingPropertiesForKeys: nil) else { return }
        var removed = false
        for file in files where file.lastPathComponent.hasPrefix("tunnel-") && file.pathExtension == "conf" {
            try? FileManager.default.removeItem(at: file)
            removed = true
        }
        if removed { Task { await reloadNginxTolerant() } }
    }

    private func selectTunnelPort(_ siteID: UUID) -> Int {
        let base = 41_000 + stablePortOffset(siteID)
        for offset in 0..<1_000 {
            let port = 41_000 + ((base - 41_000 + offset) % 10_000)
            if case .available = preflight.check(port: port) { return port }
        }
        return base
    }

    private func stablePortOffset(_ siteID: UUID) -> Int {
        siteID.uuidString.utf8.reduce(0) { ($0 &+ Int($1)) % 10_000 }
    }
}
