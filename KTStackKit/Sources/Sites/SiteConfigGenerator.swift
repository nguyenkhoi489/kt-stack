import Foundation

public struct SiteConfigGenerator {
    private let paths: AppSupportPaths
    private let writer = NginxConfigWriter()
    private let backend: WebServerBackend = NginxBackend()

    public init(paths: AppSupportPaths) {
        self.paths = paths
    }

    public func vhostText(for site: Site, port: Int) -> String {
        let hasCert = certPresent(for: site)
        let socket = site.type == .php ? paths.phpFpmSocket(effectivePHPVersion(site.phpVersion)) : nil
        let context = BackendRenderContext(
            site: site,
            root: URL(fileURLWithPath: site.docroot),
            phpFpmSocket: socket,
            nodeProxyPort: nodeProxyPort(for: site),
            certFile: hasCert ? paths.siteCert(site.domain) : nil,
            keyFile: hasCert ? paths.siteKey(site.domain) : nil,
            accessLog: paths.siteAccessLog(site.domain),
            errorLog: paths.siteErrorLog(site.domain),
            port: port
        )
        return backend.siteConfig(context: context)
    }

    private func nodeProxyPort(for site: Site) -> Int? {
        guard site.type == .node, let port = site.nodePort else { return nil }
        return port
    }

    private func certPresent(for site: Site) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: paths.siteCert(site.domain).path)
            && fm.fileExists(atPath: paths.siteKey(site.domain).path)
    }

    @discardableResult
    public func generate(sites: [Site], port: Int = 80) throws -> Bool {
        var changed = false
        let secureCatchAll = sites.contains { $0.secure && certPresent(for: $0) }
        if secureCatchAll { try NginxCatchAllCert(paths: paths).ensure() }
        changed = try writeIfChanged(
            writer.masterConfig(paths: paths, secureCatchAll: secureCatchAll),
            to: paths.nginxConf
        ) || changed

        var registeredFiles = Set<String>()
        for site in sites where NginxConfigWriter.isValidDomain(site.domain) {
            registeredFiles.insert(paths.vhost(site.domain).lastPathComponent)
        }

        for site in sites {
            guard NginxConfigWriter.isValidDomain(site.domain),
                  NginxConfigWriter.isSafePath(site.docroot)
            else {
                NSLog("KTStack: skipping site with invalid domain/path: \(site.domain)")
                continue
            }
            changed = try writeIfChanged(vhostText(for: site, port: port), to: paths.vhost(site.domain)) || changed
        }

        changed = removeOrphanVhosts(keeping: registeredFiles) || changed
        return changed
    }

    public static func requiredVersions(for sites: [Site]) -> Set<String> {
        Set(sites.filter { $0.type == .php }.map(\.phpVersion))
    }

    private func installedPHP() -> [String] {
        BundledPHP.availableVersions(php: paths.phpRuntimesRoot)
    }

    public func effectivePHPVersion(_ requested: String) -> String {
        let installed = installedPHP()
        if installed.contains(requested) { return requested }
        return installed.max { $0.compare($1, options: .numeric) == .orderedAscending } ?? requested
    }

    public func poolVersions(for sites: [Site]) -> Set<String> {
        Set(sites.filter { $0.type == .php }.map { effectivePHPVersion($0.phpVersion) })
    }

    private func writeIfChanged(_ content: String, to url: URL) throws -> Bool {
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == content {
            return false
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    private func removeOrphanVhosts(keeping desired: Set<String>) -> Bool {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: paths.sitesEnabled,
            includingPropertiesForKeys: nil
        ) else { return false }
        var removed = false
        for file in files where file.pathExtension == "conf"
            && !desired.contains(file.lastPathComponent)
            && !file.lastPathComponent.hasPrefix("tunnel-")
        {
            try? fm.removeItem(at: file)
            removed = true
        }
        return removed
    }
}
