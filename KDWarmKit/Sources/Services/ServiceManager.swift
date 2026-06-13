import Foundation
import Combine

/// Single aggregation point for the Services view and the menu bar. Publishes one `ServiceSnapshot`
/// per `ServiceKind`, refreshed by a sub-second health poll (design §1.2). It is a CONTROLLER over
/// launchd jobs (and the DNS helper) — it never parents the processes, so services persist across
/// app quit and this just reflects/derives their live state.
///
/// nginx + php-fpm are owned by `LocalServerController` (their lifecycle is driven by the site
/// registry), so this delegates those two to it; the databases, Mailpit and dnsmasq are owned here.
@MainActor
public final class ServiceManager: ObservableObject {
    /// Fixed display order (design §5.2 / wireframe).
    public static let order: [ServiceKind] = [.nginx, .phpFpm, .dnsmasq, .mysql, .postgres, .redis, .mailpit]

    @Published public private(set) var snapshots: [ServiceSnapshot] = []

    private let server: LocalServerController
    private let dns: DNSAutomationService
    private let paths: AppSupportPaths
    private let agents: LaunchAgentManager
    /// Independently-supervised services (databases, Mailpit, dnsmasq-proxy). nginx/php-fpm excluded.
    private let services: [ServiceKind: ManagedService]
    private let restart = RestartPolicy()
    private var busy: Set<ServiceKind> = []
    private var pollTask: Task<Void, Never>?
    /// On-demand DB engine install: catalog + downloader + per-kind progress/error/task.
    private let catalog: ServiceBinaryCatalog
    private let downloader: RuntimeDownloader
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
            .mailpit:  MailpitController(paths: paths, agents: agents),
        ]
        snapshots = Self.order.map { ServiceSnapshot(kind: $0, status: .stopped, detail: "", isInstalled: true) }

        // nginx/php/dns status changes are driven by their own controllers (a toggle flips them
        // synchronously). Mirror those into the published snapshots IMMEDIATELY instead of waiting up
        // to one ~0.9s poll cycle — otherwise a Start/Stop tap looks unresponsive until the next poll
        // (the reported "have to switch tabs and back" lag). `receive(on:)` defers the read until after
        // the controller's @Published value has committed (objectWillChange fires pre-change).
        server.objectWillChange
            .merge(with: dns.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncControllerSnapshots() }
            .store(in: &cancellables)
    }

    /// Refresh just the controller-owned rows (nginx/php-fpm web slice + dnsmasq) from their live
    /// state — cheap, no network probe — so a toggle reflects instantly. The poll still owns the
    /// DB/Mailpit rows and re-derives everything authoritatively each cycle.
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

    /// Begin the health poll. Safe to call once (idempotent).
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

    /// Toggle a single service. nginx/php-fpm drive the whole web slice via the server controller;
    /// the rest start/stop their own launchd job (or, for dnsmasq, the helper-owned DNS job).
    public func toggle(_ kind: ServiceKind) {
        let running = snapshot(kind)?.status == .running
        switch kind {
        case .nginx, .phpFpm:
            server.toggle()
        default:
            guard let svc = services[kind] else { return }
            perform(kind) { running ? try await svc.stop() : try await svc.start() }
        }
    }

    /// Restart a single service (overflow menu / error-banner CTA). nginx/php-fpm restart the web
    /// slice via the server; the rest kickstart their launchd job.
    public func restart(_ kind: ServiceKind) {
        switch kind {
        case .nginx, .phpFpm:
            server.restart()       // one sequenced stop→start (no busy-flag race, skips own-port preflight)
        default:
            guard let svc = services[kind] else { return }
            perform(kind) { try await svc.restart() }
        }
    }

    /// Start the web slice + every installed database/Mailpit. dnsmasq is intentionally excluded —
    /// it is helper-owned and toggled explicitly in Sites (so "Start all" never triggers a sudo prompt).
    public func startAll() {
        if !server.isRunning { server.start() }
        for kind in [ServiceKind.mysql, .postgres, .redis, .mailpit] {
            guard let svc = services[kind], svc.isInstalled else { continue }
            perform(kind) { try await svc.start() }
        }
    }

    /// Stop the web slice + every database/Mailpit launchd job (boots them out so they stay down).
    /// dnsmasq is left running (infrastructure, helper-owned).
    public func stopAll() {
        if server.isRunning { server.stop() }
        for kind in [ServiceKind.mysql, .postgres, .redis, .mailpit] {
            guard let svc = services[kind] else { continue }
            perform(kind) { try await svc.stop() }
        }
    }

    // MARK: - On-demand engine install

    /// Download + install a DB engine on demand (verified, into `runtimes/<engine>/<version>/`).
    /// No-op if it's already installing or has no catalog release.
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
        // The next poll recomputes the snapshot; the engine now resolves as installed on success.
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
        // Only publish on a real change — @Published fires objectWillChange on every set, even an
        // identical one, which would redraw the whole Services list ~1x/sec for nothing.
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
        // dnsmasq is helper-owned (no launchd label we control) — trust its probe directly.
        if kind == .dnsmasq {
            let status = await svc.probe()
            return ServiceSnapshot(kind: kind, status: status, detail: svc.detail,
                                   isInstalled: true, isBusy: busy.contains(kind))
        }
        // Only probe a loaded job — a stopped service skips the network probe so the poll stays <1s.
        let status: ServiceStatus
        if !agents.isLoaded(kind.launchdLabel) {
            restart.reset(kind)
            status = .stopped
        } else {
            // launchd keeps the job loaded across a crash + (throttled) auto-restart; the policy
            // holds `starting` through that window and only escalates to `error` on a real storm.
            let healthy = await svc.probe() == .running
            status = restart.record(kind, healthy: healthy).status
        }
        return ServiceSnapshot(kind: kind, status: status, detail: svc.detail,
                               isInstalled: true, isBusy: busy.contains(kind),
                               errorMessage: status == .error ? lastErrorMessage(kind) : nil)
    }

    private func webSnapshot(_ kind: ServiceKind, status: ServiceStatus, detail: String) -> ServiceSnapshot {
        ServiceSnapshot(kind: kind, status: status, detail: detail, isInstalled: true,
                        isBusy: server.isBusy, errorMessage: nil)
    }

    private func phpDetail() -> String {
        server.isRunning ? server.availableVersions.joined(separator: ", ") : "off"
    }

    // MARK: - Helpers

    private func snapshot(_ kind: ServiceKind) -> ServiceSnapshot? { snapshots.first { $0.kind == kind } }

    private func lastErrorMessage(_ kind: ServiceKind) -> String {
        "\(kind.displayName) kept crashing on restart. Restart it manually or check its logs."
    }

    /// Run a service action with a transient busy flag so the row shows a spinner mid-transition
    /// (design §5.3) and the error surfaces on failure.
    private func perform(_ kind: ServiceKind, _ action: @escaping @Sendable () async throws -> Void) {
        guard !busy.contains(kind) else { return }
        busy.insert(kind)
        restart.reset(kind)
        // Publish the spinner immediately. `busy` alone isn't observed — the UI reads `snapshots`, which
        // otherwise only rebuilds on the next health poll, so a DB toggle wouldn't show "loading" the
        // way nginx/php do (those flip the @Published `server.isBusy` synchronously). Flip it here too.
        setSnapshotBusy(kind, true)
        Task { [weak self] in
            var message: String?
            do { try await action() } catch { message = error.localizedDescription }
            await MainActor.run {
                guard let self else { return }
                self.busy.remove(kind)
                self.setSnapshotBusy(kind, false, errorMessage: message)
            }
            // Re-derive the real status NOW instead of waiting up to one ~0.9s poll cycle, so the
            // button flips start↔stop the instant the action finishes (no laggy 2s gap after the spinner).
            await self?.refresh()
        }
    }

    /// Reflect a kind's busy/error transition into the published `snapshots` right away (the row's
    /// spinner binds to `snapshot.isBusy`). No-op if the kind isn't in the current snapshot list.
    private func setSnapshotBusy(_ kind: ServiceKind, _ isBusy: Bool, errorMessage: String? = nil) {
        guard let idx = snapshots.firstIndex(where: { $0.kind == kind }) else { return }
        snapshots[idx].isBusy = isBusy
        if let errorMessage { snapshots[idx].errorMessage = errorMessage }
    }
}
