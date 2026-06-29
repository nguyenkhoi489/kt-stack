import Foundation

public struct HerdSiteSource: ExternalSiteSource {
    public let tool = "Herd"
    private let configFile: URL
    private let linkedDir: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let base = home.appendingPathComponent("Library/Application Support/Herd/config/valet")
        configFile = base.appendingPathComponent("config.json")
        linkedDir = base.appendingPathComponent("Sites")
    }

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: configFile.path)
    }

    public func discover() -> [DiscoveredSite] {
        ValetSiteSource.discover(tool: tool, configFile: configFile, linkedDir: linkedDir, experimental: true)
    }
}
