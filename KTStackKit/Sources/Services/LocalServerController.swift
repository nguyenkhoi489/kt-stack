import Foundation
import Combine

@MainActor
public final class LocalServerController: ObservableObject {
    @Published public private(set) var nginxStatus: ServiceStatus = .stopped
    @Published public private(set) var phpStatus: ServiceStatus = .stopped
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastError: String?

    public let httpPort = 80
    public let registry: SiteRegistry
    public var onSitesChanged: (([Site]) -> Void)?
   
    nonisolated private let tld: String

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
    nonisolated private let httpsProvisioner: SiteHTTPSProvisioner
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
        self.httpsProvisioner = SiteHTTPSProvisioner(paths: paths,
                                                     tld: tld,
                                                     mkcert: self.mkcert,
                                                     certMinter: self.certMinter)

        registry.onChange = { [weak self] in self?.onRegistryChanged() }
        watcher.onChange = { [weak self] folder in
            Task { @MainActor in self?.handleFolderChange(folder) }
        }
     
        if nginx.isRunning { reattachOnLaunch() } else { recomputeStatus() }
    }


    public func refreshStatus() {
        guard !isBusy else { return }
        recomputeStatus()
    }

   
    private func reattachOnLaunch() {
        let required = generator.poolVersions(for: registry.sites)
        _ = try? pools.reconcile(required: required)
        recomputeStatus()
        refreshWatches()
    }

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

    public var availableVersions: [String] {
        let v = BundledPHP.availableVersions(php: paths.phpRuntimesRoot)
        return v.isEmpty ? [BundledPHP.defaultVersion] : v
    }

    public func toggle() { isRunning ? stop() : start() }

  
    public func setSiteSecure(_ site: Site, _ secure: Bool) {
        guard !isBusy else { return }
        guard secure else { registry.setSecure(site, false); return }

        isBusy = true; lastError = nil
        let provisioner = self.httpsProvisioner
        Task.detached(priority: .userInitiated) {
            var failure: String?
            do {
                try provisioner.enableHTTPS(for: site)
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

   
    public func reloadPHPPool(version: String) async throws {
        let pools = self.pools
        try await Task.detached(priority: .userInitiated) {
            try pools.reload(version: version)
        }.value
    }

    
    public func restartPHPPool(version: String) async throws {
        let pools = self.pools
        try await Task.detached(priority: .userInitiated) {
            try pools.restart(version: version)
        }.value
    }

    public func start() {
        guard !isBusy, !isRunning else { return }
        isBusy = true; lastError = nil
        nginxStatus = .starting
        ensureSeed()
        let sites = registry.sites
        let port = httpPort
        Task.detached(priority: .userInitiated) { [stager, self] in
            do {
                LogRotator().rotateOversized(in: self.paths)
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
        isBusy = true; nginxStatus = .stopping; phpStatus = .stopping
        Task.detached(priority: .userInitiated) { [nginx, pools, self] in
            nginx.stop()
            pools.stopAll()
            await MainActor.run {
                self.nginxStatus = .stopped; self.phpStatus = .stopped; self.isBusy = false
                self.watcher.stop()
            }
        }
    }

    
    public func shutdownForQuit() {
        watcher.stop()
        agents.bootoutAll()
    }

    // MARK: - Independent nginx / PHP-FPM lifecycle

    public var phpRunning: Bool {
        let active = pools.activeVersions
        return !active.isEmpty && active.allSatisfy { pools.isRunning(version: $0) }
    }

    public func toggleNginx() { isRunning ? stopNginx() : startNginx() }
    public func togglePHP() { phpRunning ? stopPHP() : startPHP() }

    public func startNginx() {
        guard !isBusy, !isRunning else { return }
        isBusy = true; lastError = nil; nginxStatus = .starting
        ensureSeed()
        let sites = registry.sites
        let port = httpPort
        Task.detached(priority: .userInitiated) { [self] in
            do {
                try stager.stageIfNeeded()
                _ = try generator.generate(sites: sites, port: port)
                switch preflight.check(port: port) {
                case .available: break
                case .inUse(_, let message), .blocked(let message):
                    throw NSError(domain: "KTStack", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
                }
                try nginx.start()
                await finish(missing: [], error: nil)
            } catch {
                nginx.stop()
                await finish(missing: [], error: error.localizedDescription)
            }
        }
    }

    public func stopNginx() {
        guard !isBusy else { return }
        isBusy = true; nginxStatus = .stopping
        Task.detached(priority: .userInitiated) { [nginx, self] in
            nginx.stop()
            await MainActor.run { self.isBusy = false; self.recomputeStatus() }
        }
    }

    public func startPHP() {
        guard !isBusy, !phpRunning else { return }
        isBusy = true; lastError = nil; phpStatus = .starting
        ensureSeed()
        let sites = registry.sites
        Task.detached(priority: .userInitiated) { [self] in
            do {
                try stager.stageIfNeeded()
                _ = try pools.reconcile(required: generator.poolVersions(for: sites))
                for version in pools.activeVersions {
                    try await Self.waitForSocket(pools.socket(for: version))
                }
                let installedPHP = Set(BundledPHP.availableVersions(php: paths.phpRuntimesRoot))
                let missing = SiteConfigGenerator.requiredVersions(for: sites)
                    .subtracting(installedPHP).sorted()
                await finish(missing: missing, error: nil)
            } catch {
                pools.stopAll()
                await finish(missing: [], error: error.localizedDescription)
            }
        }
    }

    public func stopPHP() {
        guard !isBusy else { return }
        isBusy = true; phpStatus = .stopping
        Task.detached(priority: .userInitiated) { [pools, self] in
            pools.stopAll()
            await MainActor.run { self.isBusy = false; self.recomputeStatus() }
        }
    }

    public func restartNginx() {
        guard !isBusy else { return }
        isBusy = true; lastError = nil; nginxStatus = .starting
        ensureSeed()
        let sites = registry.sites
        let port = httpPort
        Task.detached(priority: .userInitiated) { [self] in
            nginx.stop()
            do {
                try stager.stageIfNeeded()
                _ = try generator.generate(sites: sites, port: port)
                try nginx.start()
                await finish(missing: [], error: nil)
            } catch {
                nginx.stop()
                await finish(missing: [], error: error.localizedDescription)
            }
        }
    }

    public func restartPHP() {
        guard !isBusy else { return }
        isBusy = true; lastError = nil; phpStatus = .starting
        ensureSeed()
        let sites = registry.sites
        Task.detached(priority: .userInitiated) { [self] in
            pools.stopAll()
            do {
                try stager.stageIfNeeded()
                _ = try pools.reconcile(required: generator.poolVersions(for: sites))
                for version in pools.activeVersions {
                    try await Self.waitForSocket(pools.socket(for: version))
                }
                await finish(missing: [], error: nil)
            } catch {
                pools.stopAll()
                await finish(missing: [], error: error.localizedDescription)
            }
        }
    }

    // MARK: - Reconcile

    private func onRegistryChanged() {
        onSitesChanged?(registry.sites)
        guard isRunning || phpRunning else { refreshWatches(); return }
        guard !isBusy else { pendingReconcile = true; return }
        reconcile()
    }

   
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

    private nonisolated func applyConfiguration(sites: [Site], port: Int, startNginx: Bool,
                                                runPreflight: Bool = true) async throws -> [String] {
        let changed = try generator.generate(sites: sites, port: port)

        let phpUp = !pools.activeVersions.isEmpty && pools.activeVersions.allSatisfy { pools.isRunning(version: $0) }
        if phpUp {
            _ = try pools.reconcile(required: generator.poolVersions(for: sites))
            for version in pools.activeVersions {
                try await Self.waitForSocket(pools.socket(for: version))
            }
        }
        let installedPHP = Set(BundledPHP.availableVersions(php: paths.phpRuntimesRoot))
        let missing = SiteConfigGenerator.requiredVersions(for: sites)
            .subtracting(installedPHP).sorted()
        if startNginx {
            if runPreflight {
                switch preflight.check(port: port) {
                case .available: break
                case .inUse(_, let m), .blocked(let m): throw NSError(domain: "KTStack", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: m])
                }
            }
            try nginx.start()
        } else if changed {
            do { try nginx.reload() }
            catch { NSLog("KTStack: nginx reload failed: \(error.localizedDescription)") }
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
    
        let nginxRunning = nginx.isRunning
        let newNginx: ServiceStatus = nginxRunning ? .running : .stopped
        let active = pools.activeVersions
        let allUp = !active.isEmpty && active.allSatisfy { pools.isRunning(version: $0) }
        let newPhp: ServiceStatus = allUp ? .running : .stopped
        if newNginx != nginxStatus { nginxStatus = newNginx }
        if newPhp != phpStatus { phpStatus = newPhp }
    }

    private func handleFolderChange(_ folder: URL) {
      
        for site in registry.sites where site.path == folder.path {
            registry.reinspect(site)
        }
    }

    private func refreshWatches() {
        watcher.watch(registry.sites.map { URL(fileURLWithPath: $0.path) })
    }

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
        throw NSError(domain: "KTStack", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "php-fpm socket did not appear in time."])
    }

    private nonisolated static func provisionSampleSite(at docroot: URL, domain: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: docroot, withIntermediateDirectories: true)
        let index = docroot.appendingPathComponent("index.php")
        guard !fm.fileExists(atPath: index.path) else { return }
        let body = """
        <?php
        // KTStack demo site — served at http://\(domain).
        echo "<h1>KTStack · \(domain) is live</h1>";
        phpinfo();
        """
        try body.write(to: index, atomically: true, encoding: .utf8)
    }
}
