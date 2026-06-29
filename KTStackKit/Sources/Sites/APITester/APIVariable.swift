import Foundation

public struct APIVariable: Codable, Hashable, Sendable {
    public var name: String
    public var value: String
    public var enabled: Bool

    public init(name: String, value: String, enabled: Bool = true) {
        self.name = name
        self.value = value
        self.enabled = enabled
    }
}

public enum APIVariableStore {
    private static let defaults = UserDefaults.standard

    private static func key(siteKey: String) -> String {
        "com.ktstack.apiTester.variables.\(siteKey)"
    }

    public static func load(siteKey: String) -> [APIVariable] {
        guard let data = defaults.data(forKey: key(siteKey: siteKey)),
              let stored = try? JSONDecoder().decode([APIVariable].self, from: data)
        else { return [] }
        return stored
    }

    public static func save(_ variables: [APIVariable], siteKey: String) {
        guard let data = try? JSONEncoder().encode(variables) else { return }
        defaults.set(data, forKey: key(siteKey: siteKey))
    }
}

public enum APIVariableInterpolator {
    public static func resolve(_ text: String, with values: [String: String]) -> String {
        guard text.contains("{{") else { return text }
        var result = ""
        var remaining = Substring(text)
        while let open = remaining.range(of: "{{") {
            result += remaining[remaining.startIndex..<open.lowerBound]
            let afterOpen = remaining[open.upperBound...]
            guard let close = afterOpen.range(of: "}}") else {
                result += remaining[open.lowerBound...]
                return result
            }
            let rawName = afterOpen[afterOpen.startIndex..<close.lowerBound]
            let name = rawName.trimmingCharacters(in: .whitespaces)
            if let value = values[name] {
                result += value
            } else {
                result += "{{" + rawName + "}}"
            }
            remaining = afterOpen[close.upperBound...]
        }
        result += remaining
        return result
    }
}
