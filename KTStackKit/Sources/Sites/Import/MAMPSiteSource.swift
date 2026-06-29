import Foundation

public struct MAMPSiteSource: ExternalSiteSource {
    public let tool = "MAMP"
    private let vhostsFile: URL

    public init(root: URL = URL(fileURLWithPath: "/Applications/MAMP")) {
        vhostsFile = root.appendingPathComponent("conf/apache/extra/httpd-vhosts.conf")
    }

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: vhostsFile.path)
    }

    public func discover() -> [DiscoveredSite] {
        guard let text = try? String(contentsOf: vhostsFile, encoding: .utf8) else { return [] }
        return Self.parseVirtualHosts(text).map {
            DiscoveredSite(
                tool: tool,
                name: URL(fileURLWithPath: $0.docroot).lastPathComponent,
                path: URL(fileURLWithPath: $0.docroot),
                domain: $0.serverName,
                phpVersion: nil,
                experimental: true
            )
        }
    }

    static func parseVirtualHosts(_ text: String) -> [(serverName: String, docroot: String)] {
        var results: [(String, String)] = []
        var serverName: String?
        var docroot: String?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("<VirtualHost") { serverName = nil; docroot = nil }
            else if line.lowercased().hasPrefix("servername") {
                serverName = value(after: "ServerName", in: line)
            } else if line.lowercased().hasPrefix("documentroot") {
                docroot = value(after: "DocumentRoot", in: line)
            } else if line.hasPrefix("</VirtualHost") {
                if let name = serverName, let root = docroot { results.append((name, root)) }
            }
        }
        return results
    }

    private static func value(after keyword: String, in line: String) -> String? {
        let trimmed = line.dropFirst(keyword.count).trimmingCharacters(in: .whitespaces)
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).isEmpty
            ? nil : trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}
