import Foundation

public struct VersionSwitcher: Sendable {
    private let paths: AppSupportPaths
    private let catalog: RuntimeCatalog
    private let resolver: VersionResolver

    public init(
        paths: AppSupportPaths,
        catalog: RuntimeCatalog? = nil,
        resolver: VersionResolver = VersionResolver()
    ) {
        self.paths = paths
        self.catalog = catalog ?? RuntimeCatalog(paths: paths)
        self.resolver = resolver
    }

    public func resolvedPHPVersion(projectDir: URL?, globalDefault: String) -> String {
        let installed = catalog.installedVersions(.php)
        let marker = projectDir.flatMap { resolver.version(.php, forProjectAt: $0) }
        for candidate in [marker, globalDefault, BundledPHP.defaultVersion] {
            if let c = candidate, installed.contains(c) { return c }
        }
        return installed.first ?? globalDefault
    }

    public func runtimeBinDir(_ lang: RuntimeLanguage, version: String) -> URL? {
        guard catalog.isInstalled(lang, version) else { return nil }
        return paths.runtimeBin(lang.rawValue, version)
    }
}
