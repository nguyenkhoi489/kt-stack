import Foundation

enum WordPressArgumentError: LocalizedError, Equatable {
    case invalidURL(String)
    case invalidTablePrefix(String)
    case invalidDatabaseName(String)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(value):
            "Refused unsafe URL from the backup: “\(value)”."
        case let .invalidTablePrefix(value):
            "Refused unsafe table prefix from the backup: “\(value)”."
        case let .invalidDatabaseName(value):
            "Refused unsafe database name: “\(value)”."
        }
    }
}

enum WordPressArgumentValidator {
    static func validateURL(_ value: String) throws -> String {
        guard !value.isEmpty, !value.hasPrefix("-"), !containsUnsafeScalars(value) else {
            throw WordPressArgumentError.invalidURL(value)
        }
        let pattern = #"^(https?://)?[A-Za-z0-9][A-Za-z0-9.\-]*(:[0-9]+)?(/[^\s]*)?$"#
        guard matches(pattern, value) else { throw WordPressArgumentError.invalidURL(value) }
        return value
    }

    static func validateTablePrefix(_ value: String) throws -> String {
        guard matches(#"^[A-Za-z0-9_]+$"#, value) else {
            throw WordPressArgumentError.invalidTablePrefix(value)
        }
        return value
    }

    static func validateDatabaseName(_ value: String) throws -> String {
        guard matches(#"^[A-Za-z0-9_]+$"#, value) else {
            throw WordPressArgumentError.invalidDatabaseName(value)
        }
        return value
    }

    static func host(of url: String) -> String {
        var value = url
        for scheme in ["https://", "http://"] where value.hasPrefix(scheme) {
            value.removeFirst(scheme.count)
        }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        return value
    }

    private static func containsUnsafeScalars(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
                || scalar == "\"" || scalar == "'" || scalar == "`" || scalar == "\\"
        }
    }

    private static func matches(_ pattern: String, _ value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}
