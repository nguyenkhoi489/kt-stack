import Foundation

public struct RouteIntrospector: Sendable {
    public struct IntrospectionError: LocalizedError {
        public let detail: String
        public init(detail: String) { self.detail = detail }
        public var errorDescription: String? { detail }
    }

    private let runner: InstallCommandRunner

    public init(php: URL, phpIni: URL?) {
        self.runner = InstallCommandRunner(php: php, phpIni: phpIni)
    }

    public func routes(siteAt folder: URL) async throws -> RouteIntrospectionOutcome {
        try ensureProjectFiles(at: folder)
        do {
            let reflected = try reflect(siteAt: folder)
            return RouteIntrospectionOutcome(routes: reflected, metadataOnly: false, warning: nil)
        } catch let error as IntrospectionError {
            return try fallback(siteAt: folder, reason: error.detail)
        } catch {
            return try fallback(siteAt: folder, reason: error.localizedDescription)
        }
    }

    private func ensureProjectFiles(at folder: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.appendingPathComponent("vendor/autoload.php").path) {
            throw IntrospectionError(detail: "Dependencies missing — run composer install in the project.")
        }
        if !fm.fileExists(atPath: folder.appendingPathComponent("bootstrap/app.php").path) {
            throw IntrospectionError(detail: "bootstrap/app.php not found — not a Laravel project root.")
        }
    }

    private func reflect(siteAt folder: URL) throws -> [APIRoute] {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-route-reflect-\(UUID().uuidString).php")
        try LaravelRouteReflectionScript.php.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let output = try runner.runPHP([scriptURL.path], cwd: folder)
        guard let data = Self.jsonSlice(from: output) else {
            throw IntrospectionError(detail: "Reflection produced no JSON output.")
        }
        let payload = try Self.parseReflectionPayload(data)
        if let error = payload.error, !error.isEmpty {
            throw IntrospectionError(detail: error)
        }
        return Self.sorted(payload.routes)
    }

    private func fallback(siteAt folder: URL, reason: String) throws -> RouteIntrospectionOutcome {
        do {
            let output = try runner.runPHP(["artisan", "route:list", "--json"], cwd: folder)
            guard let data = Self.jsonSlice(from: output) else {
                throw IntrospectionError(detail: reason)
            }
            let routes = try Self.parseRouteList(data)
            return RouteIntrospectionOutcome(
                routes: Self.sorted(routes),
                metadataOnly: true,
                warning: "Rules unavailable — showing metadata only.")
        } catch {
            throw IntrospectionError(detail: reason)
        }
    }

    struct ReflectionPayload: Decodable {
        let error: String?
        let routes: [APIRoute]
    }

    static func parseReflectionPayload(_ data: Data) throws -> ReflectionPayload {
        do {
            return try JSONDecoder().decode(ReflectionPayload.self, from: data)
        } catch {
            throw IntrospectionError(detail: "Could not parse reflection output: \(error.localizedDescription)")
        }
    }

    static func parseRouteList(_ data: Data) throws -> [APIRoute] {
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw IntrospectionError(detail: "Unexpected route:list format.")
        }
        var routes: [APIRoute] = []
        for entry in raw {
            let uri = (entry["uri"] as? String) ?? ""
            let name = entry["name"] as? String
            let action = (entry["action"] as? String) ?? "Closure"
            let middleware = parseMiddleware(entry["middleware"])
            for method in parseMethods(entry["method"]) {
                routes.append(APIRoute(method: method,
                                       uri: uri,
                                       name: (name?.isEmpty ?? true) ? nil : name,
                                       middleware: middleware,
                                       action: action,
                                       fields: [],
                                       rulesResolved: false))
            }
        }
        return routes
    }

    private static func parseMethods(_ value: Any?) -> [String] {
        let tokens: [String]
        if let array = value as? [String] {
            tokens = array
        } else if let joined = value as? String {
            tokens = joined.split(whereSeparator: { $0 == "|" || $0 == "," }).map(String.init)
        } else {
            tokens = []
        }
        let cleaned = tokens
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty && $0 != "HEAD" }
        return cleaned.isEmpty ? ["GET"] : cleaned
    }

    private static func parseMiddleware(_ value: Any?) -> [String] {
        if let array = value as? [String] {
            return array
        }
        if let joined = value as? String {
            return joined
                .split(whereSeparator: { $0 == "\n" || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    private static let beginMarker = "__KTSTACK_ROUTES_BEGIN__"
    private static let endMarker = "__KTSTACK_ROUTES_END__"

    static func jsonSlice(from output: String) -> Data? {
        if let begin = output.range(of: beginMarker),
           let end = output.range(of: endMarker, range: begin.upperBound..<output.endIndex) {
            return String(output[begin.upperBound..<end.lowerBound]).data(using: .utf8)
        }
        guard let start = output.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let opener = output[start]
        let closer: Character = opener == "{" ? "}" : "]"
        guard let end = output.lastIndex(of: closer) else { return nil }
        guard start <= end else { return nil }
        return String(output[start...end]).data(using: .utf8)
    }

    private static let methodOrder = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]

    static func sorted(_ routes: [APIRoute]) -> [APIRoute] {
        routes.sorted { lhs, rhs in
            if lhs.uri != rhs.uri { return lhs.uri < rhs.uri }
            return methodRank(lhs.method) < methodRank(rhs.method)
        }
    }

    private static func methodRank(_ method: String) -> Int {
        methodOrder.firstIndex(of: method.uppercased()) ?? methodOrder.count
    }
}
