import Foundation

public enum DestructiveGuard {
    public struct Verdict: Equatable {
        public let isDestructive: Bool
        public let reason: String?

        public init(isDestructive: Bool, reason: String?) {
            self.isDestructive = isDestructive
            self.reason = reason
        }
    }

    public static func evaluate(_ sql: String) -> Verdict {
        for statement in statements(in: sql) {
            if let reason = reason(for: statement) {
                return Verdict(isDestructive: true, reason: reason)
            }
        }
        return Verdict(isDestructive: false, reason: nil)
    }

    private static func statements(in sql: String) -> [String] {
        sql.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func reason(for statement: String) -> String? {
        func matches(_ pattern: String) -> Bool {
            statement.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if matches(#"^\s*(DROP|TRUNCATE)\b"#) {
            return "DROP/TRUNCATE permanently removes data or schema objects."
        }
        let hasWhere = matches(#"\bWHERE\b"#)
        if matches(#"^\s*DELETE\b"#), !hasWhere {
            return "DELETE without a WHERE clause removes every row in the table."
        }
        if matches(#"^\s*UPDATE\b"#), !hasWhere {
            return "UPDATE without a WHERE clause changes every row in the table."
        }
        return nil
    }
}
