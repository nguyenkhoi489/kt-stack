import Foundation

public struct SiteConfigGenerator {
    private let paths: AppSupportPaths
    private let writer = NginxConfigWriter()
    private let tls = NginxTLSVhostWriter()
    private let frontProxy = NginxFrontProxyWriter()

    public init(paths: AppSupportPaths) {
        self.paths = paths
    }

    // Front-terminator vhost for a site. PHP routes to the site's loopback backend; static and
    // node are served by the front directly, byte-for-byte as the single-process build did.
    public func frontVhostText(for site: Site) -> String {
        let secure = site.secure && certPresent(for: site)
        let access = paths.siteAccessLog(site.domain)
        let error = paths.siteErrorLog(site.domain)

        if site.type == .php {
            return frontProxy.vhost(
                domain: site.domain,
                backendPort: site.backendPort ?? 0,
                secure: secure,
                certFile: secure ? paths.siteCert(site.domain) : nil,
                keyFile: secure ? paths.siteKey(site.domain) : nil
            )
        }

        let nodeProxyPort = site.type == .node ? site.nodePort : nil
        if secure {
            return tls.redirectVhost(domain: site.domain) + "\n\n"
                + tls.secureVhost(
                    domain: site.domain,
                    root: URL(fileURLWithPath: site.docroot),
                    certFile: paths.siteCert(site.domain),
                    keyFile: paths.siteKey(site.domain),
                    phpFpmSocket: nil,
                    nodeProxyPort: nodeProxyPort,
                    accessLog: access,
                    errorLog: error
                )
        }
        if let nodeProxyPort {
            return writer.vhostNodeProxy(domain: site.domain, nodePort: nodeProxyPort, accessLog: access, errorLog: error)
        }
        return writer.vhostStatic(domain: site.domain, root: URL(fileURLWithPath: site.docroot), accessLog: access, errorLog: error)
    }

    // Standalone backend config for a PHP site, rendered by the site's engine.
    public func backendConfigText(for site: Site, backendPort: Int) -> String {
        let backend = WebServerBackendFactory.backend(for: site.serverEngine)
        let context = BackendRenderContext(
            domain: site.domain,
            root: URL(fileURLWithPath: site.docroot),
            phpFpmSocket: paths.phpFpmSocket(effectivePHPVersion(site.phpVersion)),
            backendPort: backendPort,
            secure: site.secure && certPresent(for: site),
            pidFile: paths.siteBackendPid(site.id.uuidString),
            accessLog: paths.siteAccessLog(site.domain),
            errorLog: paths.siteErrorLog(site.domain)
        )
        return backend.backendConfig(context: context)
    }

    private func certPresent(for site: Site) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: paths.siteCert(site.domain).path)
            && fm.fileExists(atPath: paths.siteKey(site.domain).path)
    }

    @discardableResult
    public func generate(sites: [Site], port _: Int = 80) throws -> Bool {
        var changed = false
        let secureCatchAll = sites.contains { $0.secure && certPresent(for: $0) }
        if secureCatchAll { try NginxCatchAllCert(paths: paths).ensure() }
        changed = try writeIfChanged(
            writer.masterConfig(paths: paths, secureCatchAll: secureCatchAll),
            to: paths.nginxConf
        ) || changed

        // "Desired" is keyed on a valid domain only; a registered site skipped this pass for an
        // unsafe path must keep its prior config, not be swept as an orphan.
        var desiredVhosts = Set<String>()
        var desiredBackends = Set<String>()
        // A PHP site with no backendPort would proxy_pass to port 0 and break the whole front,
        // so it is neither desired nor written until it has one (backfilled at controller init).
        for site in sites where NginxConfigWriter.isValidDomain(site.domain) {
            if site.type == .php, site.backendPort == nil { continue }
            desiredVhosts.insert(paths.vhost(site.domain).lastPathComponent)
            if site.type == .php {
                desiredBackends.insert(paths.siteBackendConf(site.id.uuidString).lastPathComponent)
            }
        }

        for site in sites {
            guard NginxConfigWriter.isValidDomain(site.domain),
                  NginxConfigWriter.isSafePath(site.docroot)
            else {
                NSLog("KTStack: skipping site with invalid domain/path: \(site.domain)")
                continue
            }
            if site.type == .php, site.backendPort == nil {
                NSLog("KTStack: PHP site \(site.domain) has no backendPort; not served this pass")
                continue
            }
            changed = try writeIfChanged(frontVhostText(for: site), to: paths.vhost(site.domain)) || changed

            if site.type == .php, let backendPort = site.backendPort {
                changed = try writeIfChanged(
                    backendConfigText(for: site, backendPort: backendPort),
                    to: paths.siteBackendConf(site.id.uuidString)
                ) || changed
            }
        }

        changed = removeOrphanVhosts(keeping: desiredVhosts) || changed
        changed = removeOrphanBackends(keeping: desiredBackends) || changed
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

    private func removeOrphanBackends(keeping desired: Set<String>) -> Bool {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: paths.backendsConfigDir,
            includingPropertiesForKeys: nil
        ) else { return false }
        var removed = false
        for file in files where file.pathExtension == "conf" && !desired.contains(file.lastPathComponent) {
            try? fm.removeItem(at: file)
            removed = true
        }
        return removed
    }
}
