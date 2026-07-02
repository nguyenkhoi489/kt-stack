import Foundation

public struct LogSource: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable { case service, site }
    public let id: String
    public let displayName: String
    public let kind: Kind
    public let url: URL
}

public struct LogCatalog: Sendable {
    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) {
        self.paths = paths
    }

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
        let diagURL = paths.serviceLog("diagnostics")
        if fm.fileExists(atPath: diagURL.path) {
            out.append(LogSource(id: "diagnostics", displayName: "Diagnostics", kind: .service, url: diagURL))
        }
        for domain in siteDomains.sorted() {
            for (suffix, label, url) in [
                ("access", "access", paths.siteAccessLog(domain)),
                ("error", "error", paths.siteErrorLog(domain)),
            ] {
                if fm.fileExists(atPath: url.path) {
                    out.append(LogSource(
                        id: "site-\(domain)-\(suffix)",
                        displayName: "\(domain) · \(label)",
                        kind: .site,
                        url: url
                    ))
                }
            }
        }
        return out
    }
}
