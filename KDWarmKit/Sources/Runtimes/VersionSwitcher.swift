import Foundation

/// Applies version selections to the running stack.
///
/// - PHP: resolves the version a project/site should use (marker file → global default → bundled
///   default), clamped to an INSTALLED version. The actual switch is the registry setting the site's
///   `phpVersion`, which drives the Phase 3 socket-per-pool reconcile — so a site moving from 8.3→8.1
///   gets its own pool/socket and nginx repoints + reloads. This type only computes the target.
/// - Node / on-demand languages: resolves the `bin/` dir of an installed version so child processes
///   launch with the selected runtime on PATH.
public struct VersionSwitcher: Sendable {
    private let paths: AppSupportPaths
    private let catalog: RuntimeCatalog
    private let resolver: VersionResolver

    public init(paths: AppSupportPaths,
                catalog: RuntimeCatalog? = nil,
                resolver: VersionResolver = VersionResolver()) {
        self.paths = paths
        self.catalog = catalog ?? RuntimeCatalog(paths: paths)
        self.resolver = resolver
    }

    /// Effective PHP version for a project dir: marker → global default → bundled default, then
    /// clamped to an installed version (an uninstalled pin falls back so a site never points at a
    /// phantom pool). `.kdwarmrc` being untrusted, only the installed set can win.
    public func resolvedPHPVersion(projectDir: URL?, globalDefault: String) -> String {
        let installed = catalog.installedVersions(.php)
        let marker = projectDir.flatMap { resolver.version(.php, forProjectAt: $0) }
        for candidate in [marker, globalDefault, BundledPHP.defaultVersion] {
            if let c = candidate, installed.contains(c) { return c }
        }
        return installed.first ?? globalDefault
    }

    /// `bin/` dir of an installed runtime version (for launching child processes), or nil if absent.
    public func runtimeBinDir(_ lang: RuntimeLanguage, version: String) -> URL? {
        guard catalog.isInstalled(lang, version) else { return nil }
        return paths.runtimeBin(lang.rawValue, version)
    }
}
