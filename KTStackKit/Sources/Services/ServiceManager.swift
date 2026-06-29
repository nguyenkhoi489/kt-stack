import Combine
import Foundation

@MainActor
public final class ServiceManager: ObservableObject {
    public static let order: [ServiceKind] = [.nginx, .phpFpm, .dnsmasq, .mysql, .postgres, .redis, .mongodb, .mailpit]
    static let dbCacheKinds: Set<ServiceKind> = [.mysql, .postgres, .redis, .mongodb]

    @Published public private(set) var snapshots: [ServiceSnapshot] = []

    private let server: LocalServerController
    private let dns: DNSAutomationService
    private let paths: AppSupportPaths
    private let agents: LaunchAgentManager

    private var services: [ServiceKind: ManagedService] = [:]
    private let restart = RestartPolicy()
    private var busy: Set<ServiceKind> = []
    private var pollTask: Task<Void, Never>?

    private let catalog: ServiceBinaryCatalog
    private let downloader: RuntimeDownloader
    private let metricsSampler = ServiceMetricsSampler()
    private var downloadFraction: [String: Double] = [:]
    private var installError: [String: String] = [:]
    private var installTasks: [String: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var versionStore: ServiceVersionStore

    public init(
        server: LocalServerController,
        dns: DNSAutomationService,
        paths: AppSupportPaths = AppSupportPaths()
    ) {
        self.server = server
        self.dns = dns
        self.paths = paths
        let agents = LaunchAgentManager(paths: paths)
        self.agents = agents
        let cat = ServiceBinaryCatalog(paths: paths)
        catalog = cat
        downloader = RuntimeDownloader(paths: paths)
        versionStore = ServiceVersionStore(paths: paths, catalog: cat)
        ServiceDataRelocation.runIfNeeded(paths: paths, catalog: cat)

        let mysqlProvider: () -> String? = {
            ServiceVersionStore(paths: paths, catalog: ServiceBinaryCatalog(paths: paths)).activeVersion(.mysql)
        }
        let postgresProvider: () -> String? = {
            ServiceVersionStore(paths: paths, catalog: ServiceBinaryCatalog(paths: paths)).activeVersion(.postgres)
        }
        let redisProvider: () -> String? = {
            ServiceVersionStore(paths: paths, catalog: ServiceBinaryCatalog(paths: paths)).activeVersion(.redis)
        }
        let mongoProvider: () -> String? = {
            ServiceVersionStore(paths: paths, catalog: ServiceBinaryCatalog(paths: paths)).activeVersion(.mongodb)
        }
        services = [
            .dnsmasq: DnsmasqProxyService(dns: dns),
            .mysql: MySQLController(paths: paths, agents: agents, activeVersion: mysqlProvider),
            .postgres: PostgreSQLController(paths: paths, agents: agents, activeVersion: postgresProvider),
            .redis: RedisController(paths: paths, agents: agents, activeVersion: redisProvider),
            .mongodb: MongoDBController(paths: paths, agents: agents, activeVersion: mongoProvider),
            .mailpit: MailpitController(paths: paths, agents: agents),
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
        replaceSnapshot(webSnapshot(
            .nginx,
            status: server.nginxStatus,
            detail: server.isRunning ? ":80/:443" : "off"
        ))
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

    public func stopPolling() {
        pollTask?.cancel(); pollTask = nil
    }

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
            guard let svc = services[kind], svc.isInstalled, activeInstallKey(kind) == nil else { continue }
            perform(kind) { try await svc.start() }
        }
    }

    public func stopAll() {
        if server.isRunning { server.stop() }
        for kind in [ServiceKind.mysql, .postgres, .redis, .mongodb, .mailpit] {
            guard let svc = services[kind], activeInstallKey(kind) == nil else { continue }
            perform(kind) { try await svc.stop() }
        }
    }

    public func restartAll() {
        server.restart()
        for kind in [ServiceKind.mysql, .postgres, .redis, .mongodb, .mailpit] {
            guard let svc = services[kind], svc.isInstalled, activeInstallKey(kind) == nil else { continue }
            perform(kind) { try await svc.restart() }
        }
    }

    public func install(_ kind: ServiceKind) {
        guard activeInstallKey(kind) == nil else { return }
        guard let release = catalog.availableRelease(kind) else {
            if !catalog.isInstalled(kind),
               ServiceBinaryCatalog.manifest.contains(where: { $0.kind == kind })
            {
                installError[kind.rawValue] = "\(kind.displayName) isn't available for \(ServiceBinaryCatalog.arch) yet."
            }
            return
        }
        let key = release.id
        let marker = ServiceBinaryCatalog.marker(kind) ?? ""
        let dest = catalog.installDir(release)
        downloadFraction[key] = 0
        installError[key] = nil
        installError[kind.rawValue] = nil
        let downloader = downloader
        installTasks[key] = Task { [weak self] in
            do {
                try await downloader.installArchive(
                    url: release.url, sha256: release.sha256, into: dest, markerRelPath: marker
                ) { progress in
                    Task { @MainActor [weak self] in
                        guard self?.downloadFraction[key] != nil else { return }
                        self?.downloadFraction[key] = progress.fraction
                    }
                }
                await self?.finishInstall(key, error: nil)
            } catch is CancellationError {
                await self?.finishInstall(key, error: nil)
            } catch {
                await self?.finishInstall(key, error: error.localizedDescription)
            }
        }
    }

    public func cancelInstall(_ kind: ServiceKind) {
        let prefix = "\(kind.rawValue)-"
        for key in Array(installTasks.keys) where key.hasPrefix(prefix) {
            installTasks[key]?.cancel()
            installTasks[key] = nil
            downloadFraction[key] = nil
        }
    }

    private func finishInstall(_ key: String, error: String?) {
        installTasks[key] = nil
        downloadFraction[key] = nil
        if let error { installError[key] = error }
    }

    public func installedVersions(_ kind: ServiceKind) -> [String] {
        catalog.installedVersions(kind)
    }

    public func availableReleases(_ kind: ServiceKind) -> [ServiceBinaryRelease] {
        catalog.availableReleases(kind)
    }

    public func activeVersion(_ kind: ServiceKind) -> String? {
        versionStore.activeVersion(kind)
    }

    public func setActiveVersion(_ kind: ServiceKind, version: String) throws {
        guard snapshot(kind)?.status != .running else {
            throw ServiceVersionError(message: "Stop \(kind.displayName) before switching versions.")
        }
        objectWillChange.send()
        versionStore.setActiveVersion(kind, version)
    }

    public func install(_ release: ServiceBinaryRelease) {
        let key = release.id
        guard installTasks[key] == nil, activeInstallKey(release.kind) == nil else { return }
        let marker = ServiceBinaryCatalog.marker(release.kind) ?? ""
        let dest = catalog.installDir(release)
        downloadFraction[key] = 0
        installError[key] = nil
        installError[release.kind.rawValue] = nil
        let downloader = downloader
        installTasks[key] = Task { [weak self] in
            do {
                try await downloader.installArchive(
                    url: release.url, sha256: release.sha256, into: dest, markerRelPath: marker
                ) { progress in
                    Task { @MainActor [weak self] in
                        guard self?.downloadFraction[key] != nil else { return }
                        self?.downloadFraction[key] = progress.fraction
                        self?.objectWillChange.send()
                    }
                }
                await self?.finishInstall(key, error: nil)
            } catch is CancellationError {
                await self?.finishInstall(key, error: nil)
            } catch {
                await self?.finishInstall(key, error: error.localizedDescription)
            }
        }
    }

    public func cancelInstall(_ release: ServiceBinaryRelease) {
        let key = release.id
        installTasks[key]?.cancel()
        installTasks[key] = nil
        downloadFraction[key] = nil
        objectWillChange.send()
    }

    public func uninstall(kind: ServiceKind, version: String) throws {
        if version == activeVersion(kind) {
            throw ServiceVersionError(message: "Set a different active version before uninstalling \(kind.displayName) \(version).")
        }
        if snapshot(kind)?.status == .running {
            throw ServiceVersionError(message: "Stop \(kind.displayName) before uninstalling a version.")
        }
        objectWillChange.send()
        let fm = FileManager.default
        try fm.removeItem(at: paths.runtimeDir(kind.rawValue, version))
        try? fm.removeItem(at: paths.serviceData(kind.rawValue, version: version))
        let remaining = catalog.installedVersions(kind)
        if let newActive = Self.repointedVersion(remaining: remaining, currentActive: activeVersion(kind)) {
            versionStore.setActiveVersion(kind, newActive)
        }
    }

    nonisolated static func repointedVersion(remaining: [String], currentActive: String?) -> String? {
        guard let currentActive, !remaining.contains(currentActive) else { return nil }
        return remaining.max { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    public func installProgress(for release: ServiceBinaryRelease) -> Double? {
        downloadFraction[release.id]
    }

    public func isInstallInFlight(_ kind: ServiceKind) -> Bool {
        activeInstallKey(kind) != nil
    }

    public func resetData(_ kind: ServiceKind) {
        guard let svc = services[kind] else { return }
        let paths = paths
        let version = Self.dbCacheKinds.contains(kind) ? versionStore.activeVersion(kind) : nil
        perform(kind) {
            try? await svc.stop()
            Self.removeServiceData(kind, version: version, paths: paths)
        }
    }

    public nonisolated static func removeServiceData(_ kind: ServiceKind, version: String?, paths: AppSupportPaths) {
        let target: URL
        if let v = version, dbCacheKinds.contains(kind) {
            target = paths.serviceData(kind.rawValue, version: v)
        } else {
            target = paths.serviceData(kind.rawValue)
        }
        try? FileManager.default.removeItem(at: target)
    }

    private func refresh() async {
        server.refreshStatus()
        var next: [ServiceSnapshot] = []
        for kind in Self.order {
            switch kind {
            case .nginx: next.append(webSnapshot(kind, status: server.nginxStatus, detail: server.isRunning ? ":80/:443" : "off"))
            case .phpFpm: next.append(webSnapshot(kind, status: server.phpStatus, detail: phpDetail()))
            default: await next.append(independentSnapshot(kind))
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
            let key = activeInstallKey(kind)
            let fraction = key.flatMap { downloadFraction[$0] }
            let installing = fraction != nil
            return ServiceSnapshot(
                kind: kind, status: .stopped,
                detail: installing ? "Installing…" : "Not installed",
                isInstalled: false, isBusy: busy.contains(kind),
                errorMessage: installErrorMessage(kind),
                installable: catalog.availableRelease(kind) != nil,
                downloadFraction: fraction
            )
        }

        if kind == .dnsmasq {
            let status = await svc.probe()
            return ServiceSnapshot(
                kind: kind,
                status: status,
                detail: svc.detail,
                isInstalled: true,
                isBusy: busy.contains(kind)
            )
        }

        let status: ServiceStatus
        if !agents.isLoaded(kind.launchdLabel) {
            restart.reset(kind)
            status = .stopped
        } else {
            let healthy = await svc.probe() == .running
            status = restart.record(kind, healthy: healthy).status
        }
        return ServiceSnapshot(
            kind: kind,
            status: status,
            detail: svc.detail,
            isInstalled: true,
            isBusy: busy.contains(kind),
            errorMessage: status == .error ? lastErrorMessage(kind) : nil
        )
    }

    private func activeInstallKey(_ kind: ServiceKind) -> String? {
        let prefix = "\(kind.rawValue)-"
        return downloadFraction.keys.first { $0.hasPrefix(prefix) }
    }

    private func installErrorMessage(_ kind: ServiceKind) -> String? {
        let prefix = "\(kind.rawValue)-"
        for (key, msg) in installError {
            if key.hasPrefix(prefix) || key == kind.rawValue { return msg }
        }
        return nil
    }

    private func webSnapshot(_ kind: ServiceKind, status: ServiceStatus, detail: String) -> ServiceSnapshot {
        ServiceSnapshot(
            kind: kind,
            status: status,
            detail: detail,
            isInstalled: true,
            isBusy: status == .starting || status == .stopping,
            errorMessage: nil
        )
    }

    private func phpDetail() -> String {
        server.isRunning ? server.availableVersions.joined(separator: ", ") : "off"
    }

    private func snapshot(_ kind: ServiceKind) -> ServiceSnapshot? {
        snapshots.first { $0.kind == kind }
    }

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
