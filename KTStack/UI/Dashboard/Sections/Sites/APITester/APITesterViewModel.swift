import SwiftUI
import KTStackKit

enum RouteTab: Hashable { case web, api }

enum RequestBodyMode: String, CaseIterable, Hashable {
    case none, json, form

    var label: String {
        switch self {
        case .none: return "None"
        case .json: return "JSON"
        case .form: return "Form"
        }
    }
}

struct EditablePair: Identifiable, Hashable {
    let id = UUID()
    var key: String
    var value: String
    var enabled: Bool = true
}

struct RequestDraft: Hashable {
    var pathParams: [EditablePair] = []
    var query: [EditablePair] = []
    var headers: [EditablePair] = []
    var bodyMode: RequestBodyMode = .none
    var bodyText: String = ""
}

@MainActor
final class APITesterViewModel: ObservableObject {
    @Published var routes: [APIRoute] = []
    @Published var tab: RouteTab = .web
    @Published var filter: String = ""
    @Published var selected: APIRoute?
    @Published var timeoutSeconds: Double = 30
    @Published var bodyDisplayLimitKB: Int = 200
    @Published var requestDraft = RequestDraft()
    @Published var variables: [EditablePair] = []
    @Published var isEditingVariables = false
    @Published var response: APIResponseResult?
    @Published var isLoadingRoutes = false
    @Published var isSending = false
    @Published var loadError: String?
    @Published var sendError: String?
    @Published var metadataWarning: String?
    @Published var isGenericMode = false
    @Published var draftMethod = "GET"
    @Published var draftPath = "/"

    static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]

    static let adHocRouteID = "__ktstack_adhoc__"
    static let adHocRoute = APIRoute(method: "GET", uri: adHocRouteID, name: "New request",
                                     middleware: [], action: "", fields: [], rulesResolved: true)

    private var drafts: [String: RequestDraft] = [:]
    private var siteKey = ""

    var siteDomain: String { siteKey }

    var activeVariableCount: Int {
        variables.filter { $0.enabled && !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    var webRoutes: [APIRoute] { filtered(routes.filter { !$0.isApi }) }
    var apiRoutes: [APIRoute] { filtered(routes.filter { $0.isApi }) }

    var visibleRoutes: [APIRoute] { tab == .web ? webRoutes : apiRoutes }

    var hasUnresolvedPathParams: Bool {
        requestDraft.pathParams.contains { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func filtered(_ source: [APIRoute]) -> [APIRoute] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return source }
        return source.filter {
            $0.uri.lowercased().contains(query)
                || $0.method.lowercased().contains(query)
                || ($0.name?.lowercased().contains(query) ?? false)
        }
    }

    func load(site: Site) async {
        guard !isLoadingRoutes else { return }
        isLoadingRoutes = true
        loadError = nil
        metadataWarning = nil
        siteKey = site.domain
        variables = APIVariableStore.load(siteKey: siteKey).map {
            EditablePair(key: $0.name, value: $0.value, enabled: $0.enabled)
        }
        let folder = URL(fileURLWithPath: site.path)
        guard LaravelSiteProbe().isLaravel(siteAt: folder) else {
            isGenericMode = true
            routes = []
            newRequest()
            isLoadingRoutes = false
            return
        }
        isGenericMode = false
        let paths = AppSupportPaths()
        let php = paths.phpBinary(version: site.phpVersion)
        let phpIni = paths.phpIni(version: site.phpVersion)
        do {
            let introspector = RouteIntrospector(php: php, phpIni: phpIni)
            let outcome = try await Task.detached(priority: .userInitiated) {
                try await introspector.routes(siteAt: folder)
            }.value
            routes = outcome.routes
            metadataWarning = outcome.metadataOnly ? outcome.warning : nil
            if let first = visibleRoutes.first {
                select(first)
            } else if let firstAny = routes.first {
                tab = firstAny.isApi ? .api : .web
                select(firstAny)
            } else {
                newRequest()
            }
        } catch {
            routes = []
            loadError = error.localizedDescription
        }
        isLoadingRoutes = false
    }

    func newRequest() {
        select(Self.adHocRoute)
        draftMethod = "GET"
        draftPath = "/"
    }

    var normalizedDraftPath: String {
        let trimmed = draftPath.trimmingCharacters(in: .whitespaces)
        let path = trimmed.isEmpty ? "/" : trimmed
        return path.hasPrefix("/") ? path : "/" + path
    }

    func syncPathParams() {
        let names = Self.pathParamNames(in: normalizedDraftPath)
        let existing = Dictionary(requestDraft.pathParams.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var rebuilt: [EditablePair] = []
        var seen = Set<String>()
        for name in names where !seen.contains(name) {
            seen.insert(name)
            rebuilt.append(existing[name] ?? EditablePair(key: name, value: ""))
        }
        if rebuilt.map(\.key) != requestDraft.pathParams.map(\.key) {
            requestDraft.pathParams = rebuilt
        }
    }

    func select(_ route: APIRoute) {
        if let current = selected {
            drafts[current.id] = requestDraft
        }
        selected = route
        draftMethod = route.method
        draftPath = route.uri.hasPrefix("/") ? route.uri : "/" + route.uri
        response = nil
        sendError = nil
        requestDraft = drafts[route.id] ?? Self.defaultDraft(for: route)
    }

    func saveVariables() {
        guard !siteKey.isEmpty else { return }
        let stored = variables.map { APIVariable(name: $0.key, value: $0.value, enabled: $0.enabled) }
        APIVariableStore.save(stored, siteKey: siteKey)
    }

    func resolved(_ text: String) -> String {
        APIVariableInterpolator.resolve(text, with: variableMap())
    }

    private func variableMap() -> [String: String] {
        var map: [String: String] = [:]
        for variable in variables where variable.enabled {
            let name = variable.key.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            map[name] = variable.value
        }
        return map
    }

    func send(site: Site) async {
        guard let route = selected, !isSending else { return }
        isSending = true
        sendError = nil
        response = nil
        saveVariables()
        drafts[route.id] = requestDraft
        do {
            let spec = try buildSpec(route: route, site: site)
            let client = APIRequestClient(timeout: timeoutSeconds)
            response = try await client.send(spec)
        } catch {
            sendError = error.localizedDescription
        }
        isSending = false
    }

    func buildSpec(route: APIRoute, site: Site) throws -> APIRequestSpec {
        guard let url = composeURL(route: route, site: site) else {
            throw APIRequestClient.RequestError(message: "Could not build a valid request URL.")
        }
        var headers = requestDraft.headers
            .filter { $0.enabled && !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { ($0.key, resolved($0.value)) }
        let body = encodedBody()
        if let body, !body.isEmpty, !headers.contains(where: { $0.0.lowercased() == "content-type" }) {
            headers.append(("Content-Type", contentType()))
        }
        return APIRequestSpec(method: draftMethod, url: url, headers: headers, body: body)
    }

    private func composeURL(route: APIRoute, site: Site) -> URL? {
        let scheme = site.secure ? "https" : "http"
        var path = normalizedDraftPath
        for param in requestDraft.pathParams {
            let raw = resolved(param.value)
            let value = raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
            path = path.replacingOccurrences(of: "{\(param.key)?}", with: value)
            path = path.replacingOccurrences(of: "{\(param.key)}", with: value)
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = site.domain
        components.path = path
        let items = requestDraft.query
            .filter { $0.enabled && !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { URLQueryItem(name: $0.key, value: resolved($0.value)) }
        if !items.isEmpty { components.queryItems = items }
        return components.url
    }

    private func encodedBody() -> Data? {
        switch requestDraft.bodyMode {
        case .none:
            return nil
        case .json:
            let text = resolved(requestDraft.bodyText)
            return text.isEmpty ? nil : text.data(using: .utf8)
        case .form:
            return Self.encodeForm(resolved(requestDraft.bodyText))
        }
    }

    static func encodeForm(_ text: String) -> Data? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let pairs = text
            .split(whereSeparator: { $0 == "\n" || $0 == "&" })
            .map { line -> String in
                let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(parts.first ?? "").trimmingCharacters(in: .whitespaces)
                let value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .filter { $0 != "=" }
        let joined = pairs.joined(separator: "&")
        return joined.isEmpty ? nil : joined.data(using: .utf8)
    }

    private func contentType() -> String {
        switch requestDraft.bodyMode {
        case .json: return "application/json"
        case .form: return "application/x-www-form-urlencoded"
        case .none: return "application/octet-stream"
        }
    }

    static func defaultDraft(for route: APIRoute) -> RequestDraft {
        var draft = RequestDraft()
        draft.headers = [EditablePair(key: "Accept", value: "application/json")]
        draft.pathParams = pathParamNames(in: route.uri).map { EditablePair(key: $0, value: "") }
        let writesBody = !["GET", "HEAD", "DELETE", "OPTIONS"].contains(route.method.uppercased())
        if writesBody, !route.fields.isEmpty {
            draft.bodyMode = .json
            draft.bodyText = bodySkeleton(fields: route.fields)
        }
        return draft
    }

    static func pathParamNames(in uri: String) -> [String] {
        var names: [String] = []
        var current = ""
        var inside = false
        for ch in uri {
            if ch == "{" { inside = true; current = "" }
            else if ch == "}" {
                inside = false
                let cleaned = current.hasSuffix("?") ? String(current.dropLast()) : current
                if !cleaned.isEmpty { names.append(cleaned) }
            } else if inside {
                current.append(ch)
            }
        }
        return names
    }

    static func bodySkeleton(fields: [APIRouteRuleField]) -> String {
        let required = fields.filter { $0.required }
        let chosen = required.isEmpty ? fields : required
        guard !chosen.isEmpty else { return "{\n  \n}" }
        let lines = chosen.map { "  \"\($0.name)\": \"\"" }.joined(separator: ",\n")
        return "{\n\(lines)\n}"
    }
}
