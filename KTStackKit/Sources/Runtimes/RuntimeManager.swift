import Combine
import Foundation

@MainActor
public final class RuntimeManager: ObservableObject {
    public struct DownloadState: Sendable, Equatable {
        public var version: String
        public var received: Int64
        public var total: Int64
        public var error: String?
        public var fraction: Double {
            total > 0 ? min(1, Double(received) / Double(total)) : 0
        }
    }

    @Published public private(set) var installed: [RuntimeLanguage: [String]] = [:]
    @Published public private(set) var downloads: [RuntimeLanguage: DownloadState] = [:]
    @Published public private(set) var globalDefaults: [RuntimeLanguage: String] = [:]

    private let paths: AppSupportPaths
    private let catalog: RuntimeCatalog
    private let downloader: RuntimeDownloader
    private var tasks: [RuntimeLanguage: Task<Void, Never>] = [:]
    private var defaultsURL: URL {
        paths.config.appendingPathComponent("runtimes.json")
    }

    public init(paths: AppSupportPaths = AppSupportPaths()) {
        self.paths = paths
        catalog = RuntimeCatalog(paths: paths)
        downloader = RuntimeDownloader(paths: paths)
        loadDefaults()
        refreshInstalled()
        reconcilePHPExtensionConfig()
    }

    private func reconcilePHPExtensionConfig() {
        let installer = PHPExtensionInstaller(paths: paths)
        for version in installed[.php] ?? [] {
            try? installer.writeExtensionDirIni(phpVersion: version)
            installer.writeBaseExtensionInis(phpVersion: version)
        }
    }

    public func refreshInstalled() {
        var map: [RuntimeLanguage: [String]] = [:]
        for lang in RuntimeLanguage.allCases {
            map[lang] = catalog.installedVersions(lang)
        }
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

    public func defaultVersion(_ lang: RuntimeLanguage) -> String? {
        globalDefaults[lang]
    }

    public func isDownloading(_ lang: RuntimeLanguage) -> Bool {
        downloads[lang] != nil && downloads[lang]?.error == nil
    }

    public func install(_ release: RuntimeRelease) {
        guard !isDownloading(release.language) else { return }
        downloads[release.language] = DownloadState(version: release.version, received: 0, total: -1)
        let downloader = downloader
        let paths = paths
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

                if lang == .php {
                    PHPModules.invalidate(version: version)
                    let installer = PHPExtensionInstaller(paths: paths)
                    try? installer.writeExtensionDirIni(phpVersion: version)
                    installer.writeBaseExtensionInis(phpVersion: version)
                }
                await self?.finish(lang, error: nil)
            } catch is CancellationError {
                await self?.finish(lang, error: nil)
            } catch {
                await self?.finish(lang, error: error.localizedDescription)
            }
        }
    }

    public func cancel(_ lang: RuntimeLanguage) {
        tasks[lang]?.cancel()
        tasks[lang] = nil
        downloads[lang] = nil
    }

    public func setGlobalDefault(_ lang: RuntimeLanguage, _ version: String) {
        globalDefaults[lang] = version
        persistDefaults()
    }

    public func uninstall(_ lang: RuntimeLanguage, _ version: String) {
        if downloads[lang]?.version == version, downloads[lang]?.error == nil { cancel(lang) }

        let fm = FileManager.default
        if lang == .php {
            let label = "com.ktstack.php-fpm.\(version)"
            try? LaunchAgentManager(paths: paths).bootout(label)
            try? fm.removeItem(at: paths.launchAgentPlist(label))
            try? fm.removeItem(at: paths.phpFpmSocket(version))
            try? fm.removeItem(at: paths.phpFpmPid(version))
            try? fm.removeItem(at: paths.phpFpmLog(version))
            try? fm.removeItem(at: paths.phpFpmPool(version))
            try? fm.removeItem(at: paths.phpIniDir(version: version))
            PHPModules.invalidate(version: version)
        }

        do { try fm.removeItem(at: paths.runtimeDir(lang.rawValue, version)) }
        catch { NSLog("KTStack: uninstall \(lang.rawValue) \(version) failed: \(error.localizedDescription)") }

        if globalDefaults[lang] == version {
            globalDefaults[lang] = catalog.installedVersions(lang).first { $0 != version }
            persistDefaults()
        }
        refreshInstalled()
    }

    private func finish(_ lang: RuntimeLanguage, error: String?) {
        tasks[lang] = nil
        if let error {
            downloads[lang]?.error = error // keep the row so the card shows failure + retry
        } else {
            downloads[lang] = nil
            refreshInstalled()
        }
    }

    private func loadDefaults() {
        guard let data = try? Data(contentsOf: defaultsURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        for (k, v) in map {
            if let lang = RuntimeLanguage(rawValue: k) { globalDefaults[lang] = v }
        }
    }

    private func persistDefaults() {
        let map = Dictionary(uniqueKeysWithValues: globalDefaults.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? FileManager.default.createDirectory(at: paths.config, withIntermediateDirectories: true)
        try? data.write(to: defaultsURL, options: .atomic)
    }
}
