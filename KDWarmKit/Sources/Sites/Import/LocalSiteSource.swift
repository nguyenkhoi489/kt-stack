import Foundation

public struct LocalSiteSource: ExternalSiteSource {
    public let tool = "Local"
    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    private var candidateFiles: [URL] {
        ["Local", "Local by Flywheel"].map {
            home.appendingPathComponent("Library/Application Support/\($0)/sites.json")
        }
    }

    public var isAvailable: Bool {
        candidateFiles.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func discover() -> [DiscoveredSite] {
        guard let file = candidateFiles.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return root.values.compactMap(parse)
    }

    private func parse(_ value: Any) -> DiscoveredSite? {
        guard let dict = value as? [String: Any],
              let path = dict["path"] as? String, !path.isEmpty else { return nil }
        let name = (dict["name"] as? String) ?? URL(fileURLWithPath: path).lastPathComponent
        let domain = (dict["domain"] as? String) ?? "\(SiteInspector.slug(name)).local"
        let php = phpVersion(from: dict)
        return DiscoveredSite(tool: tool, name: name, path: URL(fileURLWithPath: path),
                              domain: domain, phpVersion: php)
    }

    private func phpVersion(from dict: [String: Any]) -> String? {
        guard let services = dict["services"] as? [String: Any],
              let php = services["php"] as? [String: Any],
              let version = php["version"] as? String else { return nil }
        return ProjectVersionResolver.majorMinor(fromConstraint: version)
    }
}
