import Foundation

public struct OpenAPIRouteDiscovery: Sendable {
    public init() {}

    static let candidatePaths = [
        "/openapi.json", "/swagger.json", "/swagger/v1/swagger.json",
        "/v3/api-docs", "/api-docs", "/api-docs.json", "/docs.json",
    ]

    static let httpMethods = ["get", "post", "put", "patch", "delete", "options"]
    static let maxBytes = 16_000_000

    public func discover(baseURL: URL, timeout: TimeInterval = 4) async -> [APIRoute] {
        for candidate in Self.candidatePaths {
            guard let url = URL(string: candidate, relativeTo: baseURL) else { continue }
            guard let spec = await fetchJSON(url, timeout: timeout) else { continue }
            let routes = Self.parse(spec)
            if !routes.isEmpty { return routes }
        }
        return []
    }

    private func fetchJSON(_ url: URL, timeout: TimeInterval) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= Self.maxBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    static func parse(_ spec: [String: Any]) -> [APIRoute] {
        guard let paths = spec["paths"] as? [String: Any] else { return [] }
        let basePath = serverBasePath(spec)
        var routes: [APIRoute] = []
        for (rawPath, value) in paths {
            guard let operations = value as? [String: Any] else { continue }
            let fullPath = joinPath(basePath, rawPath)
            for method in httpMethods {
                guard let operation = operations[method] else { continue }
                let summary = (operation as? [String: Any])?["summary"] as? String
                let operationId = (operation as? [String: Any])?["operationId"] as? String
                routes.append(APIRoute(
                    method: method.uppercased(),
                    uri: normalizedURI(fullPath),
                    name: summary ?? operationId,
                    middleware: [],
                    action: "",
                    fields: [],
                    rulesResolved: false
                ))
            }
        }
        return sorted(routes)
    }

    private static func serverBasePath(_ spec: [String: Any]) -> String {
        if let servers = spec["servers"] as? [[String: Any]],
           let first = servers.first, let urlString = first["url"] as? String
        {
            if let url = URL(string: urlString), !url.path.isEmpty { return url.path }
            if urlString.hasPrefix("/") { return urlString }
        }
        if let basePath = spec["basePath"] as? String { return basePath }
        return ""
    }

    private static func joinPath(_ base: String, _ path: String) -> String {
        let left = base.hasSuffix("/") ? String(base.dropLast()) : base
        let right = path.hasPrefix("/") ? path : "/" + path
        return left + right
    }

    private static func normalizedURI(_ path: String) -> String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }

    private static let methodOrder = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]

    static func sorted(_ routes: [APIRoute]) -> [APIRoute] {
        routes.sorted { lhs, rhs in
            if lhs.uri != rhs.uri { return lhs.uri < rhs.uri }
            let li = methodOrder.firstIndex(of: lhs.method.uppercased()) ?? methodOrder.count
            let ri = methodOrder.firstIndex(of: rhs.method.uppercased()) ?? methodOrder.count
            return li < ri
        }
    }
}
