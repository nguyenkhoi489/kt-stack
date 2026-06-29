import Foundation

public struct PostmanCollectionDiscovery: Sendable {
    static let maxBytes = 16_000_000

    public init() {}

    public func discover(folder: URL, fileManager: FileManager = .default) -> [APIRoute] {
        guard let file = locateCollection(folder: folder, fileManager: fileManager),
              ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) <= Self.maxBytes,
              let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["item"] as? [[String: Any]]
        else { return [] }
        var routes: [APIRoute] = []
        Self.collect(items: items, into: &routes)
        return OpenAPIRouteDiscovery.sorted(dedup(routes))
    }

    private func locateCollection(folder: URL, fileManager: FileManager) -> URL? {
        let candidates = [folder] + ((try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        for dir in candidates {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            if let match = entries.first(where: { $0.lastPathComponent.lowercased().contains("postman_collection") }) {
                return match
            }
        }
        return nil
    }

    static func collect(items: [[String: Any]], into routes: inout [APIRoute]) {
        for item in items {
            if let nested = item["item"] as? [[String: Any]] {
                collect(items: nested, into: &routes)
            }
            guard let request = item["request"] else { continue }
            let name = item["name"] as? String
            if let route = route(from: request, name: name) { routes.append(route) }
        }
    }

    static func route(from request: Any, name: String?) -> APIRoute? {
        let method: String
        let urlValue: Any?
        if let dict = request as? [String: Any] {
            method = (dict["method"] as? String)?.uppercased() ?? "GET"
            urlValue = dict["url"]
        } else if let string = request as? String {
            method = "GET"
            urlValue = string
        } else {
            return nil
        }
        guard method != "HEAD", let path = path(from: urlValue) else { return nil }
        return APIRoute(
            method: method,
            uri: path,
            name: name,
            middleware: [],
            action: "",
            fields: [],
            rulesResolved: false
        )
    }

    static func path(from urlValue: Any?) -> String? {
        if let dict = urlValue as? [String: Any] {
            if let segments = dict["path"] as? [Any] {
                let parts = segments.compactMap { seg -> String? in
                    if let s = seg as? String { return normalizeSegment(s) }
                    if let d = seg as? [String: Any], let v = d["value"] as? String { return normalizeSegment(v) }
                    return nil
                }
                if !parts.isEmpty { return parts.joined(separator: "/") }
            }
            if let raw = dict["raw"] as? String { return pathFromRaw(raw) }
            return nil
        }
        if let raw = urlValue as? String { return pathFromRaw(raw) }
        return nil
    }

    private static func pathFromRaw(_ raw: String) -> String? {
        var working = raw
        if let queryStart = working.firstIndex(of: "?") { working = String(working[..<queryStart]) }
        for token in ["{{base_url}}", "{{baseUrl}}", "{{base_path}}", "{{basePath}}"] {
            working = working.replacingOccurrences(of: token, with: "")
        }
        if let schemeRange = working.range(of: "://") {
            let afterScheme = working[schemeRange.upperBound...]
            working = afterScheme.firstIndex(of: "/").map { String(afterScheme[$0...]) } ?? ""
        }
        var segments = working.split(separator: "/").map(String.init)
        if let first = segments.first, first.hasPrefix("{{"), first.hasSuffix("}}") {
            segments.removeFirst()
        }
        let parts = segments.map(normalizeSegment).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    private static func normalizeSegment(_ segment: String) -> String {
        if segment.hasPrefix(":") { return "{\(segment.dropFirst())}" }
        if segment.hasPrefix("{{"), segment.hasSuffix("}}"), segment.count > 4 {
            return "{\(segment.dropFirst(2).dropLast(2))}"
        }
        return segment
    }

    private func dedup(_ routes: [APIRoute]) -> [APIRoute] {
        var seen = Set<String>()
        return routes.filter { seen.insert($0.id).inserted }
    }
}
