import Foundation

public struct APIRouteRuleField: Sendable, Hashable, Codable {
    public let name: String
    public let rules: [String]
    public let required: Bool

    public init(name: String, rules: [String], required: Bool) {
        self.name = name
        self.rules = rules
        self.required = required
    }
}

public struct APIRoute: Sendable, Identifiable, Hashable, Codable {
    public var id: String {
        method + " " + uri
    }

    public let method: String
    public let uri: String
    public let name: String?
    public let middleware: [String]
    public let action: String
    public let fields: [APIRouteRuleField]
    public let rulesResolved: Bool

    public init(
        method: String,
        uri: String,
        name: String?,
        middleware: [String],
        action: String,
        fields: [APIRouteRuleField],
        rulesResolved: Bool
    ) {
        self.method = method
        self.uri = uri
        self.name = name
        self.middleware = middleware
        self.action = action
        self.fields = fields
        self.rulesResolved = rulesResolved
    }

    enum CodingKeys: String, CodingKey {
        case method, uri, name, middleware, action, fields, rulesResolved
    }

    public var isApi: Bool {
        middleware.contains { $0.lowercased() == "api" }
    }

    public var isClosure: Bool {
        action == "Closure" || !action.contains("@")
    }
}

public struct RouteIntrospectionOutcome: Sendable {
    public let routes: [APIRoute]
    public let metadataOnly: Bool
    public let warning: String?

    public init(routes: [APIRoute], metadataOnly: Bool, warning: String?) {
        self.routes = routes
        self.metadataOnly = metadataOnly
        self.warning = warning
    }
}
