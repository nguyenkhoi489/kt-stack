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
    /// The live dev TLD (configurable, Phase 5), injected from `AppPreferences` at launch. Used for
    /// the demo-site seed domain + the cert SAN guard; the registry validates against the same value.
    nonisolated private let tld: String

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

    public init(bundleBinDir: URL, paths: AppSupportPaths = AppSupportPaths(),
                tld: String = AppPreferences.defaultTLD) {
        self.paths = paths
        self.tld = tld
        self.agents = LaunchAgentManager(paths: paths)
        self.registry = SiteRegistry(
            storeURL: paths.sitesRegistryFile,
            tld: tld,
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
        let required = generator.poolVersions(for: registry.sites)
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

    /// PHP versions whose binary is actually installed (the per-site picker offers only these).
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
        let caCert = self.paths.caRootCert, tld = self.tld
        Task.detached(priority: .userInitiated) {
            var failure: String?
            do {
                if !CATrustService.isTrustedInSystemKeychain(caCert: caCert) {
                    try mkcert.install()        // generate + trust the CA (idempotent; prompts once)
                }
                try minter.mint(name: domain, domain: domain, tld: tld)
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

    /// Restart one PHP version's pool so it re-reads its edited `php.ini` (the editor's Save). Throws
    /// if the kickstart fails so the caller can offer to revert; no-op if that version isn't running.
    public func reloadPHPPool(version: String) async throws {
        let pools = self.pools
        try await Task.detached(priority: .userInitiated) {
            try pools.reload(version: version)
        }.value
    }

    /// Fully restart one PHP version's pool (bootout + re-bootstrap) so a newly installed/uninstalled
    /// extension `.so` is actually (un)loaded and the current launchd spec (incl. `PHP_INI_SCAN_DIR`)
    /// applies. No-op if that version isn't running.
    public func restartPHPPool(version: String) async throws {
        let pools = self.pools
        try await Task.detached(priority: .userInitiated) {
            try pools.restart(version: version)
        }.value
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
                LogRotator().rotateOversized(in: self.paths)   // keep dev logs bounded; rotate on start
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

    /// Called from `applicationWillTerminate`. Stop EVERY KDWarm launchd service (nginx, php-fpm
    /// pools, databases, Mailpit) so nothing is left running once the app quits, plus the in-process
    /// folder watcher. `bootoutAll` is synchronous — one `launchctl bootout` per `com.kdwarm.*` job —
    /// so it finishes inside the synchronous terminate handler; SIGTERM lets mysqld shut down cleanly.
    /// (The root-owned dnsmasq/DNS helper is in a separate domain and intentionally persists.)
    public func shutdownForQuit() {
        watcher.stop()
        agents.bootoutAll()
    }

    // MARK: - Reconcile

    private func onRegistryChanged() {
        guard isRunning else { refreshWatches(); return }
        guard !isBusy else { pendingReconcile = true; return }
        reconcile()
    }

    /// Re-apply web config after a runtime install/uninstall changed which PHP versions exist, so
    /// vhosts re-route to the now-effective version and pools reconcile (a site whose pinned version
    /// was just removed falls back to an installed one). No-op while the server is stopped.
    public func reconcileAfterRuntimeChange() { onRegistryChanged() }

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
    /// required PHP versions whose binary isn't installed (surfaced as a non-fatal warning).
    private nonisolated func applyConfiguration(sites: [Site], port: Int, startNginx: Bool,
                                                runPreflight: Bool = true) async throws -> [String] {
        let changed = try generator.generate(sites: sites, port: port)
        // Reconcile pools for the EFFECTIVE (fallback-resolved) versions so every vhost has a live
        // upstream; the warning below reports any PINNED version that isn't installed (now served on
        // a fallback) so the substitution isn't silent.
        _ = try pools.reconcile(required: generator.poolVersions(for: sites))
        let installedPHP = Set(BundledPHP.availableVersions(php: paths.phpRuntimesRoot))
        let missing = SiteConfigGenerator.requiredVersions(for: sites)
            .subtracting(installedPHP).sorted()
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
            let pins = missing.joined(separator: ", ")
            let installed = BundledPHP.availableVersions(php: paths.phpRuntimesRoot)
            if let fallback = installed.max(by: { $0.compare($1, options: .numeric) == .orderedAscending }) {
                // Sites still serve — on a fallback version — so flag it as a warning, not a failure.
                lastError = "PHP \(pins) not installed — those sites are running on PHP \(fallback) for now. "
                    + "Install \(pins) from Runtimes to use the pinned version."
            } else {
                lastError = "PHP \(pins) not installed and no PHP is available — those sites won't serve. "
                    + "Install PHP from Runtimes."
            }
        }
        recomputeStatus()
        refreshWatches()
        certMinter.pruneOrphans(keeping: Set(registry.sites.map(\.domain)))   // drop removed sites' leaves
        if pendingReconcile { pendingReconcile = false; reconcile() }
    }

    private func recomputeStatus() {
        // Assign only on a real change. The sub-second health poll calls this every tick; setting an
        // identical @Published value still fires objectWillChange, which would re-render every view
        // observing the server (the whole dashboard) ~1x/sec and make navigation feel sluggish.
        let nginxRunning = nginx.isRunning
        let newNginx: ServiceStatus = nginxRunning ? .running : .stopped
        let active = pools.activeVersions
        let allUp = !active.isEmpty && active.allSatisfy { pools.isRunning(version: $0) }
        let anyPHP = registry.sites.contains { $0.type == .php }
        let newPhp: ServiceStatus = allUp ? .running : (anyPHP && nginxRunning ? .error : .stopped)
        if newNginx != nginxStatus { nginxStatus = newNginx }
        if newPhp != phpStatus { phpStatus = newPhp }
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
        try? Self.provisionSampleSite(at: demo.appendingPathComponent("public", isDirectory: true), domain: "demo.\(tld)")
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
