import Foundation

public struct ValetSiteSource: ExternalSiteSource {
    public let tool = "Valet"
    private let configFile: URL
    private let linkedDir: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        configFile = home.appendingPathComponent(".config/valet/config.json")
        linkedDir = home.appendingPathComponent(".config/valet/Sites")
    }

    public var isAvailable: Bool { FileManager.default.fileExists(atPath: configFile.path) }

    public func discover() -> [DiscoveredSite] {
        Self.discover(tool: tool, configFile: configFile, linkedDir: linkedDir, experimental: false)
    }

    static func discover(tool: String, configFile: URL, linkedDir: URL, experimental: Bool) -> [DiscoveredSite] {
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let tld = (config["tld"] as? String) ?? "test"
        let fm = FileManager.default
        var sites: [DiscoveredSite] = []
        var seen = Set<String>()

        func append(name: String, path: URL) {
            let domain = "\(SiteInspector.slug(name)).\(tld)"
            let site = DiscoveredSite(tool: tool, name: name, path: path, domain: domain,
                                      phpVersion: nil, experimental: experimental)
            if seen.insert(site.id).inserted { sites.append(site) }
        }

        for parked in (config["paths"] as? [String]) ?? [] {
            let root = URL(fileURLWithPath: parked)
            let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles])) ?? []
            for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                append(name: entry.lastPathComponent, path: entry)
            }
        }

        let links = (try? fm.contentsOfDirectory(at: linkedDir, includingPropertiesForKeys: nil,
                                                 options: [.skipsHiddenFiles])) ?? []
        for link in links {
            let resolved = URL(fileURLWithPath: (link.path as NSString).resolvingSymlinksInPath)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue else { continue }
            append(name: link.deletingPathExtension().lastPathComponent, path: resolved)
        }
        return sites
    }
}
