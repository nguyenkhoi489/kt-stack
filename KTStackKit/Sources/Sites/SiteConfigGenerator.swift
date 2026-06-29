import Foundation

public struct SiteConfigGenerator {
    private let paths: AppSupportPaths
    private let writer = NginxConfigWriter()
    private let tls = NginxTLSVhostWriter()

    public init(paths: AppSupportPaths) {
        self.paths = paths
    }

    public func vhostText(for site: Site, port: Int) -> String {
        let root = URL(fileURLWithPath: site.docroot)

        let socket = site.type == .php ? paths.phpFpmSocket(effectivePHPVersion(site.phpVersion)) : nil
        let access = paths.siteAccessLog(site.domain)
        let error = paths.siteErrorLog(site.domain)

        let nodeProxyPort = nodeProxyPort(for: site)

        if site.secure, certPresent(for: site) {
            return tls.redirectVhost(domain: site.domain) + "\n\n"
                + tls.secureVhost(
                    domain: site.domain,
                    root: root,
                    certFile: paths.siteCert(site.domain),
                    keyFile: paths.siteKey(site.domain),
                    phpFpmSocket: socket,
                    nodeProxyPort: nodeProxyPort,
                    accessLog: access,
                    errorLog: error
                )
        }
        switch site.type {
        case .php:
            return writer.vhost(
                domain: site.domain,
                root: root,
                phpFpmSocket: socket!,
                port: port,
                accessLog: access,
                errorLog: error
            )
        case .node where nodeProxyPort != nil:
            return writer.vhostNodeProxy(
                domain: site.domain,
                nodePort: nodeProxyPort!,
                port: port,
                accessLog: access,
                errorLog: error
            )
        case .staticSite, .node:
            return writer.vhostStatic(
                domain: site.domain,
                root: root,
                port: port,
                accessLog: access,
                errorLog: error
            )
        }
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
