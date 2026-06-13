import Foundation
import Combine

/// Aggregates runtime state for the Runtimes view + menu-bar switcher: which versions are installed,
/// in-flight downloads (determinate progress), and the global default per language. Owns the
/// download lifecycle (start/cancel) and persists global defaults to `config/runtimes.json`.
@MainActor
public final class RuntimeManager: ObservableObject {
    /// Live state of one language's download (absent when idle; kept with `error` set on failure).
    public struct DownloadState: Sendable, Equatable {
        public var version: String
        public var received: Int64
        public var total: Int64
        public var error: String?
        public var fraction: Double { total > 0 ? min(1, Double(received) / Double(total)) : 0 }
    }

    @Published public private(set) var installed: [RuntimeLanguage: [String]] = [:]
    @Published public private(set) var downloads: [RuntimeLanguage: DownloadState] = [:]
    @Published public private(set) var globalDefaults: [RuntimeLanguage: String] = [:]

    private let paths: AppSupportPaths
    private let catalog: RuntimeCatalog
    private let downloader: RuntimeDownloader
    private var tasks: [RuntimeLanguage: Task<Void, Never>] = [:]
    private var defaultsURL: URL { paths.config.appendingPathComponent("runtimes.json") }

    public init(paths: AppSupportPaths = AppSupportPaths()) {
        self.paths = paths
        self.catalog = RuntimeCatalog(paths: paths)
        self.downloader = RuntimeDownloader(paths: paths)
        loadDefaults()
        refreshInstalled()
    }

    // MARK: - Queries

    public func refreshInstalled() {
        var map: [RuntimeLanguage: [String]] = [:]
        for lang in RuntimeLanguage.allCases { map[lang] = catalog.installedVersions(lang) }
        installed = map
        // Seed the PHP default once a version is installed (first launch stages 8.4).
        if globalDefaults[.php] == nil, let php = installed[.php]?.first {
            globalDefaults[.php] = installed[.php]?.contains(BundledPHP.defaultVersion) == true
                ? BundledPHP.defaultVersion : php
            persistDefaults()
        }
    }

    public func availableReleases(_ lang: RuntimeLanguage) -> [RuntimeRelease] {
        catalog.availableReleases(lang)
    }

    public func defaultVersion(_ lang: RuntimeLanguage) -> String? { globalDefaults[lang] }

    public func isDownloading(_ lang: RuntimeLanguage) -> Bool {
        downloads[lang] != nil && downloads[lang]?.error == nil
    }

    // MARK: - Actions

    /// Start (or restart after an error) a download. No-op if one is already in flight.
    public func install(_ release: RuntimeRelease) {
        guard !isDownloading(release.language) else { return }
        downloads[release.language] = DownloadState(version: release.version, received: 0, total: -1)
        let downloader = self.downloader
        let lang = release.language
        let version = release.version
        tasks[lang] = Task { [weak self] in
            do {
                try await downloader.install(release) { progress in
                    Task { @MainActor [weak self] in
                        // Only update a live, non-errored row — a cancel may have removed it.
                        guard self?.downloads[lang] != nil, self?.downloads[lang]?.error == nil else { return }
                        self?.downloads[lang]?.received = progress.received
                        self?.downloads[lang]?.total = progress.total
                    }
                }
                // Drop any cached `php -m` for this version: a same-version reinstall (e.g. upgrading to
                // a rebuilt artifact with a wider extension set) keeps the installed list identical, so
                // the card's extension display would otherwise stay stale until relaunch.
                if lang == .php { PHPModules.invalidate(version: version) }
                await self?.finish(lang, error: nil)
            } catch is CancellationError {
                await self?.finish(lang, error: nil)
            } catch {
                await self?.finish(lang, error: error.localizedDescription)
            }
        }
    }

    /// Cancel an in-flight download (removes any partial — the downloader leaves nothing behind).
    public func cancel(_ lang: RuntimeLanguage) {
        tasks[lang]?.cancel()
        tasks[lang] = nil
        downloads[lang] = nil
    }

    /// Set the global default version for a language (used for new sites' PHP + child-proc PATH).
    public func setGlobalDefault(_ lang: RuntimeLanguage, _ version: String) {
        globalDefaults[lang] = version
        persistDefaults()
    }

    /// Remove an installed runtime version. Stops any (possibly stale) php-fpm pool for the version,
    /// deletes its binary tree + per-version config/launchd artifacts, reassigns the global default
    /// to another installed version if it pointed here, then refreshes. Best-effort on the auxiliary
    /// files (own, 0700) — the marker is the version dir, whose removal flips `isInstalled` to false.
    /// The caller must guard against versions still referenced by sites; this only deletes files.
    public func uninstall(_ lang: RuntimeLanguage, _ version: String) {
        // A mid-flight download is writing into this version's tree — cancel it before deleting.
        if downloads[lang]?.version == version, downloads[lang]?.error == nil { cancel(lang) }

        let fm = FileManager.default
        if lang == .php {
            let label = "com.kdwarm.php-fpm.\(version)"
            try? LaunchAgentManager(paths: paths).bootout(label)
            try? fm.removeItem(at: paths.launchAgentPlist(label))
            try? fm.removeItem(at: paths.phpFpmSocket(version))
            try? fm.removeItem(at: paths.phpFpmPid(version))
            try? fm.removeItem(at: paths.phpFpmLog(version))
            try? fm.removeItem(at: paths.phpFpmPool(version))
            try? fm.removeItem(at: paths.phpIniDir(version: version))
            PHPModules.invalidate(version: version)
        }

        // Removing the version dir drops its marker binary → the catalog stops listing it.
        do { try fm.removeItem(at: paths.runtimeDir(lang.rawValue, version)) }
        catch { NSLog("KDWarm: uninstall \(lang.rawValue) \(version) failed: \(error.localizedDescription)") }

        // Hand the global default to another installed version (or drop it if none remain).
        if globalDefaults[lang] == version {
            globalDefaults[lang] = catalog.installedVersions(lang).first { $0 != version }
            persistDefaults()
        }
        refreshInstalled()
    }

    // MARK: - Private

    private func finish(_ lang: RuntimeLanguage, error: String?) {
        tasks[lang] = nil
        if let error {
            downloads[lang]?.error = error            // keep the row so the card shows failure + retry
        } else {
            downloads[lang] = nil
            refreshInstalled()
        }
    }

    private func loadDefaults() {
        guard let data = try? Data(contentsOf: defaultsURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        for (k, v) in map { if let lang = RuntimeLanguage(rawValue: k) { globalDefaults[lang] = v } }
    }

    private func persistDefaults() {
        let map = Dictionary(uniqueKeysWithValues: globalDefaults.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? FileManager.default.createDirectory(at: paths.config, withIntermediateDirectories: true)
        try? data.write(to: defaultsURL, options: .atomic)
    }
}
