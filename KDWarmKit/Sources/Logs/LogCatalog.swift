import Foundation

/// A tailable log source for the Logs viewer — a service log or a per-site nginx log.
public struct LogSource: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable { case service, site }
    public let id: String
    public let displayName: String
    public let kind: Kind
    public let url: URL
}

/// Enumerates the tailable log files from the canonical app-support layout. Core sources
/// (nginx, active php-fpm pools) are always listed; database/Mailpit and per-site logs appear once
/// their file exists (i.e. the service/site has run). The tail reader tolerates a not-yet-created
/// file, so listing a core source before its first write is fine.
public struct LogCatalog: Sendable {
    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) { self.paths = paths }

    public func sources(siteDomains: [String], phpVersions: [String]) -> [LogSource] {
        let fm = FileManager.default
        var out: [LogSource] = [
            LogSource(id: "nginx-error", displayName: "Nginx · error", kind: .service, url: paths.nginxErrorLog),
            LogSource(id: "nginx-access", displayName: "Nginx · access", kind: .service, url: paths.nginxAccessLog),
        ]
        for v in phpVersions.sorted() {
            out.append(LogSource(id: "php-\(v)", displayName: "PHP-FPM \(v)", kind: .service, url: paths.phpFpmLog(v)))
        }
        for svc in ["mysql", "postgres", "redis", "mongodb", "mailpit"] {
            let url = paths.serviceLog(svc)
            if fm.fileExists(atPath: url.path) {
                out.append(LogSource(id: svc, displayName: svc.capitalized, kind: .service, url: url))
            }
        }
        for domain in siteDomains.sorted() {
            for (suffix, label, url) in [("access", "access", paths.siteAccessLog(domain)),
                                         ("error", "error", paths.siteErrorLog(domain))] {
                if fm.fileExists(atPath: url.path) {
                    out.append(LogSource(id: "site-\(domain)-\(suffix)", displayName: "\(domain) · \(label)",
                                         kind: .site, url: url))
                }
            }
        }
        return out
    }
}
