import Foundation
import Combine

@MainActor
public final class ServiceManager: ObservableObject {
   
    public static let order: [ServiceKind] = [.nginx, .phpFpm, .dnsmasq, .mysql, .postgres, .redis, .mongodb, .mailpit]

    @Published public private(set) var snapshots: [ServiceSnapshot] = []

    private let server: LocalServerController
    private let dns: DNSAutomationService
    private let paths: AppSupportPaths
    private let agents: LaunchAgentManager
    
    private let services: [ServiceKind: ManagedService]
    private let restart = RestartPolicy()
    private var busy: Set<ServiceKind> = []
    private var pollTask: Task<Void, Never>?
   
    private let catalog: ServiceBinaryCatalog
    private let downloader: RuntimeDownloader
    private let metricsSampler = ServiceMetricsSampler()
    private var downloadFraction: [ServiceKind: Double] = [:]
    private var installError: [ServiceKind: String] = [:]
    private var installTasks: [ServiceKind: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()

    public init(server: LocalServerController, dns: DNSAutomationService,
                paths: AppSupportPaths = AppSupportPaths()) {
        self.server = server
        self.dns = dns
        self.paths = paths
        let agents = LaunchAgentManager(paths: paths)
        self.agents = agents
        self.catalog = ServiceBinaryCatalog(paths: paths)
        self.downloader = RuntimeDownloader(paths: paths)
        self.services = [
            .dnsmasq:  DnsmasqProxyService(dns: dns),
            .mysql:    MySQLController(paths: paths, agents: agents),
            .postgres: PostgreSQLController(paths: paths, agents: agents),
            .redis:    RedisController(paths: paths, agents: agents),
            .mongodb:  MongoDBController(paths: paths, agents: agents),
            .mailpit:  MailpitController(paths: paths, agents: agents),
        ]
        snapshots = Self.order.map { ServiceSnapshot(kind: $0, status: .stopped, detail: "", isInstalled: true) }

      
        server.objectWillChange
            .merge(with: dns.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncControllerSnapshots() }
            .store(in: &cancellables)
    }

    private func syncControllerSnapshots() {
        guard !snapshots.isEmpty else { return }
        replaceSnapshot(webSnapshot(.nginx, status: server.nginxStatus,
                                    detail: server.isRunning ? ":80/:443" : "off"))
        replaceSnapshot(webSnapshot(.phpFpm, status: server.phpStatus, detail: phpDetail()))
    }

    private func replaceSnapshot(_ snap: ServiceSnapshot) {
        if let i = snapshots.firstIndex(where: { $0.kind == snap.kind }), snapshots[i] != snap {
            snapshots[i] = snap
        }
    }

   
    public func startPolling(interval: TimeInterval = 0.9) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stopPolling() { pollTask?.cancel(); pollTask = nil }

    // MARK: - Actions


    public func toggle(_ kind: ServiceKind) {
        let running = snapshot(kind)?.status == .running
        switch kind {
        case .nginx:
            server.toggleNginx()
        case .phpFpm:
            server.togglePHP()
        default:
            guard let svc = services[kind] else { return }
            perform(kind) { running ? try await svc.stop() : try await svc.start() }
        }
    }

    public func restart(_ kind: ServiceKind) {
        switch kind {
        case .nginx:
            server.restartNginx()
        case .phpFpm:
            server.restartPHP()
        default:
            guard let svc = services[kind] else { return }
            perform(kind) { try await svc.restart() }
        }
    }

    public func startAll() {
        if !server.isRunning { server.start() }
        for kind in [ServiceKind.mysql, .postgres, .redis, .mongodb, .mailpit] {

            guard let svc = services[kind], svc.isInstalled, installTasks[kind] == nil else { continue }
            perform(kind) { try await svc.start() }
        }
    }


    public func stopAll() {
        if server.isRunning { server.stop() }
        for kind in [ServiceKind.mysql, .postgres, .redis, .mongodb, .mailpit] {
            guard let svc = services[kind], installTasks[kind] == nil else { continue }
            perform(kind) { try await svc.stop() }
        }
    }

    public func restartAll() {
        server.restart()
        for kind in [ServiceKind.mysql, .postgres, .redis, .mongodb, .mailpit] {
            guard let svc = services[kind], svc.isInstalled, installTasks[kind] == nil else { continue }
            perform(kind) { try await svc.restart() }
        }
    }

    // MARK: - On-demand engine install

    public func install(_ kind: ServiceKind) {
        guard installTasks[kind] == nil, let release = catalog.availableRelease(kind) else { return }
        let marker = ServiceBinaryCatalog.marker(kind) ?? ""
        let dest = catalog.installDir(release)
        downloadFraction[kind] = 0
        installError[kind] = nil
        let downloader = self.downloader
        installTasks[kind] = Task { [weak self] in
            do {
                try await downloader.installArchive(
                    url: release.url, sha256: release.sha256, into: dest, markerRelPath: marker
                ) { progress in
                    Task { @MainActor [weak self] in
                        guard self?.downloadFraction[kind] != nil else { return }
                        self?.downloadFraction[kind] = progress.fraction
                    }
                }
                await self?.finishInstall(kind, error: nil)
            } catch is CancellationError {
                await self?.finishInstall(kind, error: nil)
            } catch {
                await self?.finishInstall(kind, error: error.localizedDescription)
            }
        }
    }

    public func cancelInstall(_ kind: ServiceKind) {
        installTasks[kind]?.cancel()
        installTasks[kind] = nil
        downloadFraction[kind] = nil
    }

    private func finishInstall(_ kind: ServiceKind, error: String?) {
        installTasks[kind] = nil
        downloadFraction[kind] = nil
        if let error { installError[kind] = error }
        
    }

    // MARK: - Reset data (unclean-shutdown escape hatch)

    public func resetData(_ kind: ServiceKind) {
        guard let svc = services[kind] else { return }
        let paths = self.paths
        perform(kind) {
            try? await svc.stop()
            Self.removeServiceData(kind, paths: paths)
        }
    }

    nonisolated public static func removeServiceData(_ kind: ServiceKind, paths: AppSupportPaths) {
        try? FileManager.default.removeItem(at: paths.serviceData(kind.rawValue))
    }

    // MARK: - Polling

    private func refresh() async {
        server.refreshStatus()
        var next: [ServiceSnapshot] = []
        for kind in Self.order {
            switch kind {
            case .nginx:  next.append(webSnapshot(kind, status: server.nginxStatus, detail: server.isRunning ? ":80/:443" : "off"))
            case .phpFpm: next.append(webSnapshot(kind, status: server.phpStatus, detail: phpDetail()))
            default:      next.append(await independentSnapshot(kind))
            }
        }

        let metrics = await metricsSampler.sample()
        for index in next.indices where next[index].status == .running {
            next[index].cpuPercent = metrics[next[index].kind]?.cpuPercent
            next[index].memoryBytes = metrics[next[index].kind]?.memoryBytes
        }

        if next != snapshots { snapshots = next }
    }

    private func independentSnapshot(_ kind: ServiceKind) async -> ServiceSnapshot {
        guard let svc = services[kind] else {
            return ServiceSnapshot(kind: kind, status: .stopped, detail: "", isInstalled: false)
        }
        guard svc.isInstalled else {
            let installing = downloadFraction[kind] != nil
            return ServiceSnapshot(
                kind: kind, status: .stopped,
                detail: installing ? "Installing…" : "Not installed",
                isInstalled: false, isBusy: busy.contains(kind),
                errorMessage: installError[kind],
                installable: catalog.availableRelease(kind) != nil,
                downloadFraction: downloadFraction[kind])
        }
      
        if kind == .dnsmasq {
            let status = await svc.probe()
            return ServiceSnapshot(kind: kind, status: status, detail: svc.detail,
                                   isInstalled: true, isBusy: busy.contains(kind))
        }
     
        let status: ServiceStatus
        if !agents.isLoaded(kind.launchdLabel) {
            restart.reset(kind)
            status = .stopped
        } else {
            
            let healthy = await svc.probe() == .running
            status = restart.record(kind, healthy: healthy).status
        }
        return ServiceSnapshot(kind: kind, status: status, detail: svc.detail,
                               isInstalled: true, isBusy: busy.contains(kind),
                               errorMessage: status == .error ? lastErrorMessage(kind) : nil)
    }

    private func webSnapshot(_ kind: ServiceKind, status: ServiceStatus, detail: String) -> ServiceSnapshot {
        ServiceSnapshot(kind: kind, status: status, detail: detail, isInstalled: true,
                        isBusy: status == .starting || status == .stopping, errorMessage: nil)
    }

    private func phpDetail() -> String {
        server.isRunning ? server.availableVersions.joined(separator: ", ") : "off"
    }

    // MARK: - Helpers

    private func snapshot(_ kind: ServiceKind) -> ServiceSnapshot? { snapshots.first { $0.kind == kind } }

    private func lastErrorMessage(_ kind: ServiceKind) -> String {
        "\(kind.displayName) kept crashing on restart. Restart it manually or check its logs."
    }

   
    private func perform(_ kind: ServiceKind, _ action: @escaping @Sendable () async throws -> Void) {
        guard !busy.contains(kind) else { return }
        busy.insert(kind)
        restart.reset(kind)
        
        setSnapshotBusy(kind, true)
        Task { [weak self] in
            var message: String?
            do { try await action() } catch { message = error.localizedDescription }
            await MainActor.run {
                guard let self else { return }
                self.busy.remove(kind)
                self.setSnapshotBusy(kind, false, errorMessage: message)
            }
            
            await self?.refresh()
        }
    }

    private func setSnapshotBusy(_ kind: ServiceKind, _ isBusy: Bool, errorMessage: String? = nil) {
        guard let idx = snapshots.firstIndex(where: { $0.kind == kind }) else { return }
        snapshots[idx].isBusy = isBusy
        if let errorMessage { snapshots[idx].errorMessage = errorMessage }
    }
}
