import Foundation
import Combine

/// Orchestrates the multi-site web stack: nginx + one php-fpm pool per active PHP version,
/// driven by the `SiteRegistry`. On start it stages binaries, generates a vhost per registered
/// site, reconciles the pool set, and boots nginx. While running, any registry change (add /
/// remove / edit-domain / version / folder-watch re-inspect) regenerates configs, reconciles
/// pools, and hot-reloads nginx.
///
/// Children are dev-shim processes killed on app quit (Phase 6 promotes them to launchd).
@MainActor
public final class LocalServerController: ObservableObject {
    @Published public private(set) var nginxStatus: ServiceStatus = .stopped
    @Published public private(set) var phpStatus: ServiceStatus = .stopped
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastError: String?

    public let httpPort = 80
    public let registry: SiteRegistry

    // These collaborators are Sendable and used from the off-main `applyConfiguration` work, so
    // they are explicitly nonisolated (avoids a Swift 6 main-actor isolation error).
    nonisolated private let paths: AppSupportPaths
    nonisolated private let agents: LaunchAgentManager
    nonisolated private let nginx: NginxController
    nonisolated private let pools: PHPFPMPoolManager
    nonisolated private let generator: SiteConfigGenerator
    nonisolated private let stager: BinaryStager
    nonisolated private let preflight = PortPreflight()
    nonisolated private let watcher = RegisteredSiteWatcher()
    nonisolated private let mkcert: MkcertRunner
    nonisolated private let certMinter: CertMinter
    private var didSeed = false
    private var pendingReconcile = false

    public init(bundleBinDir: URL, paths: AppSupportPaths = AppSupportPaths()) {
        self.paths = paths
        self.agents = LaunchAgentManager(paths: paths)
        self.registry = SiteRegistry(
            storeURL: paths.sitesRegistryFile,
            installedPHP: { BundledPHP.availableVersions(php: paths.phpRuntimesRoot) })
        self.nginx = NginxController(paths: paths, agents: agents)
        self.pools = PHPFPMPoolManager(paths: paths, agents: agents)
        self.generator = SiteConfigGenerator(paths: paths)
        self.stager = BinaryStager(bundleBinDir: bundleBinDir, paths: paths)
        self.mkcert = MkcertRunner(mkcert: paths.mkcertBinary, caroot: paths.caDir)
        self.certMinter = CertMinter(paths: paths, runner: MkcertRunner(mkcert: paths.mkcertBinary, caroot: paths.caDir))

        registry.onChange = { [weak self] in self?.onRegistryChanged() }
        watcher.onChange = { [weak self] folder in
            Task { @MainActor in self?.handleFolderChange(folder) }
        }
        // Reattach: services may already be running (launchd) from a previous session — reflect that
        // and resume watching so site edits keep reconciling without a re-spawn.
        if nginx.isRunning { reattachOnLaunch() } else { recomputeStatus() }
    }

    /// Re-derive published status from the live launchd/socket state. Called by the Service Manager's
    /// health poll because launchd (not the app) now supervises restarts — there is no exit callback.
    /// No-ops while an operation is in flight so a poll can't flash a transient `error` mid-start.
    public func refreshStatus() {
        guard !isBusy else { return }
        recomputeStatus()
    }

    /// Rebuild the in-memory pool map from the registry so it matches the launchd jobs that survived
    /// the last app quit (`bootstrap` is idempotent → reattach, never re-spawn). Without this the pool
    /// map is empty on launch and php-fpm would be mislabeled `error` despite serving fine.
    private func reattachOnLaunch() {
        let required = SiteConfigGenerator.requiredVersions(for: registry.sites)
        _ = try? pools.reconcile(required: required)
        recomputeStatus()
        refreshWatches()
    }

    /// Restart the whole web slice (overflow menu / error-banner CTA): boot out nginx + pools, then
    /// start fresh. Runs as ONE sequenced operation so the start half can't be dropped by the async
    /// stop's busy flag, and skips the `:80` pre-flight (we are intentionally re-binding our own port).
    public func restart() {
        guard !isBusy else { return }
        isBusy = true; lastError = nil
        nginxStatus = .starting; phpStatus = .starting
        ensureSeed()
        let sites = registry.sites
        let port = httpPort
        Task.detached(priority: .userInitiated) { [self] in
            nginx.stop(); pools.stopAll()
            do {
                try stager.stageIfNeeded()
                let missing = try await applyConfiguration(sites: sites, port: port, startNginx: true, runPreflight: false)
                await finish(missing: missing, error: nil)
            } catch {
                pools.stopAll(); nginx.stop()
                await finish(missing: [], error: error.localizedDescription)
            }
        }
    }

    public var isRunning: Bool { nginxStatus == .running }

    /// PHP versions whose binary is actually bundled (the per-site picker offers only these).
    public var availableVersions: [String] {
        let v = BundledPHP.availableVersions(php: paths.phpRuntimesRoot)
        return v.isEmpty ? [BundledPHP.defaultVersion] : v
    }

    public func toggle() { isRunning ? stop() : start() }

    /// Flip a site between http and https. Securing mints a leaf (ensuring the CA is trusted first,
    /// one GUI prompt), then sets the flag so the reconcile regenerates an https vhost + reloads.
    /// Un-securing keeps the cert (cheap re-enable) and regenerates as plain http.
    public func setSiteSecure(_ site: Site, _ secure: Bool) {
        guard !isBusy else { return }
        guard secure else { registry.setSecure(site, false); return }

        isBusy = true; lastError = nil
        let mkcert = self.mkcert, minter = self.certMinter, domain = site.domain
        let caCert = self.paths.caRootCert
        Task.detached(priority: .userInitiated) {
            var failure: String?
            do {
                if !CATrustService.isTrustedInSystemKeychain(caCert: caCert) {
                    try mkcert.install()        // generate + trust the CA (idempotent; prompts once)
                }
                try minter.mint(name: domain, domain: domain)
            } catch {
                failure = error.localizedDescription
            }
            await MainActor.run {
                self.isBusy = false
                if let failure { self.lastError = failure }
                else { self.registry.setSecure(site, true) }   // → onRegistryChanged → reconcile
            }
        }
    }

    public func start() {
        guard !isBusy, !isRunning else { return }
        isBusy = true; lastError = nil
        nginxStatus = .starting; phpStatus = .starting
        ensureSeed()
        let sites = registry.sites
        let port = httpPort
        Task.detached(priority: .userInitiated) { [stager, self] in
            do {
                try stager.stageIfNeeded()
                let missing = try await self.applyConfiguration(sites: sites, port: port, startNginx: true)
                await self.finish(missing: missing, error: nil)
            } catch {
                self.pools.stopAll(); self.nginx.stop()
                await self.finish(missing: [], error: error.localizedDescription)
            }
        }
    }

    public func stop() {
        guard !isBusy else { return }
        isBusy = true
        Task.detached(priority: .userInitiated) { [nginx, pools, self] in
            nginx.stop()
            pools.stopAll()
            await MainActor.run {
                self.nginxStatus = .stopped; self.phpStatus = .stopped; self.isBusy = false
                self.watcher.stop()
            }
        }
    }

    /// Called from `applicationWillTerminate`. Services are launchd-managed and PERSIST across app
    /// quit (Herd's model) — so we do NOT stop nginx/php-fpm here; we only stop the in-process folder
    /// watcher. Bringing everything down is the explicit "Stop all" action, not a side effect of quit.
    public func shutdownForQuit() {
        watcher.stop()
    }

    // MARK: - Reconcile

    private func onRegistryChanged() {
        guard isRunning else { refreshWatches(); return }
        guard !isBusy else { pendingReconcile = true; return }
        reconcile()
    }

    private func reconcile() {
        isBusy = true
        let sites = registry.sites
        let port = httpPort
        Task.detached(priority: .userInitiated) { [self] in
            do {
                let missing = try await self.applyConfiguration(sites: sites, port: port, startNginx: false)
                await self.finish(missing: missing, error: nil)
            } catch {
                await self.finish(missing: [], error: error.localizedDescription)
            }
        }
    }

    /// Generate vhosts → reconcile pools → wait for sockets → start or reload nginx. Returns the
    /// required PHP versions whose binary isn't bundled yet (surfaced as a non-fatal warning).
    private nonisolated func applyConfiguration(sites: [Site], port: Int, startNginx: Bool,
                                                runPreflight: Bool = true) async throws -> [String] {
        let changed = try generator.generate(sites: sites, port: port)
        let missing = try pools.reconcile(required: SiteConfigGenerator.requiredVersions(for: sites))
        for version in pools.activeVersions {
            try await Self.waitForSocket(pools.socket(for: version))
        }
        if startNginx {
            if runPreflight {
                switch preflight.check(port: port) {
                case .available: break
                case .inUse(_, let m), .blocked(let m): throw NSError(domain: "KDWarm", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: m])
                }
            }
            try nginx.start()
        } else if changed {
            do { try nginx.reload() }
            catch { NSLog("KDWarm: nginx reload failed: \(error.localizedDescription)") }
        }
        return missing
    }

    // MARK: - State

    private func finish(missing: [String], error: String?) {
        isBusy = false
        if let error { lastError = error }
        else if !missing.isEmpty {
            lastError = "PHP \(missing.joined(separator: ", ")) not bundled yet (arrives in Phase 7); those sites won't serve."
        }
        recomputeStatus()
        refreshWatches()
        certMinter.pruneOrphans(keeping: Set(registry.sites.map(\.domain)))   // drop removed sites' leaves
        if pendingReconcile { pendingReconcile = false; reconcile() }
    }

    private func recomputeStatus() {
        nginxStatus = nginx.isRunning ? .running : .stopped
        let active = pools.activeVersions
        let allUp = !active.isEmpty && active.allSatisfy { pools.isRunning(version: $0) }
        let anyPHP = registry.sites.contains { $0.type == .php }
        phpStatus = allUp ? .running : (anyPHP && nginx.isRunning ? .error : .stopped)
    }

    private func handleFolderChange(_ folder: URL) {
        // Re-inspect only the matching registered site; registry.onChange drives the reconcile.
        for site in registry.sites where site.path == folder.path {
            registry.reinspect(site)
        }
    }

    private func refreshWatches() {
        watcher.watch(registry.sites.map { URL(fileURLWithPath: $0.path) })
    }

    /// Seed a demo PHP site on first run so a fresh install has something to serve.
    private func ensureSeed() {
        guard !didSeed, registry.sites.isEmpty else { didSeed = true; return }
        didSeed = true
        let demo = AppSupportPaths.defaultSitesRoot.appendingPathComponent("demo", isDirectory: true)
        try? Self.provisionSampleSite(at: demo.appendingPathComponent("public", isDirectory: true), domain: "demo.test")
        try? registry.add(folder: demo)
    }

    private nonisolated static func waitForSocket(_ url: URL, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(domain: "KDWarm", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "php-fpm socket did not appear in time."])
    }

    private nonisolated static func provisionSampleSite(at docroot: URL, domain: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: docroot, withIntermediateDirectories: true)
        let index = docroot.appendingPathComponent("index.php")
        guard !fm.fileExists(atPath: index.path) else { return }
        let body = """
        <?php
        // KDWarm demo site — served at http://\(domain).
        echo "<h1>KDWarm · \(domain) is live</h1>";
        phpinfo();
        """
        try body.write(to: index, atomically: true, encoding: .utf8)
    }
}
