import Foundation

public enum SQLCompletionEngine {
    private static let resultLimit = 50

    private static let aliasExclusions: Set<String> = [
        "ON", "WHERE", "GROUP", "ORDER", "HAVING", "LIMIT", "OFFSET", "JOIN",
        "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "UNION", "AS",
        "USING", "SET", "VALUES", "SELECT", "FROM",
    ]

    public static func completions(
        text: String,
        caret: Int,
        catalog: SchemaCatalog,
        keywords: [String]
    ) -> [SQLCompletionItem] {
        let chars = Array(text)
        let position = max(0, min(caret, chars.count))
        let token = currentToken(chars, caret: position)

        if let qualifier = token.qualifier {
            let aliases = parseTableAliases(text)
            let table = aliases[qualifier.lowercased()] ?? qualifier
            let columns = catalog.columns(of: table).map { SQLCompletionItem(text: $0, kind: .column) }
            return rank(columns, partial: token.partial)
        }

        guard !token.partial.isEmpty else { return [] }

        let aliases = parseTableAliases(text)
        let fromTables = Set(aliases.values)
        let columnNames = collectColumnNames(catalog: catalog, fromTables: fromTables)

        var candidates: [SQLCompletionItem] = []
        candidates += keywords.map { SQLCompletionItem(text: $0, kind: .keyword) }
        candidates += catalog.tables.map { SQLCompletionItem(text: $0, kind: .table) }
        candidates += columnNames.map { SQLCompletionItem(text: $0, kind: .column) }
        return rank(candidates, partial: token.partial)
    }

    private static func collectColumnNames(catalog: SchemaCatalog, fromTables: Set<String>) -> [String] {
        guard !fromTables.isEmpty else { return catalog.allColumnNames }
        var seen = Set<String>()
        var names: [String] = []
        for table in fromTables.sorted() {
            for column in catalog.columns(of: table) where seen.insert(column.lowercased()).inserted {
                names.append(column)
            }
        }
        return names
    }

    private static func isIdentifier(_ char: Character) -> Bool {
        char == "_" || char.isLetter || char.isNumber
    }

    private static func currentToken(_ chars: [Character], caret: Int) -> (qualifier: String?, partial: String) {
        var start = caret
        while start > 0, isIdentifier(chars[start - 1]) {
            start -= 1
        }
        let partial = String(chars[start..<caret])

        guard start > 0, chars[start - 1] == "." else { return (nil, partial) }
        var qualifierStart = start - 1
        while qualifierStart > 0, isIdentifier(chars[qualifierStart - 1]) {
            qualifierStart -= 1
        }
        let qualifier = String(chars[qualifierStart..<(start - 1)])
        return (qualifier.isEmpty ? nil : qualifier, partial)
    }

    private static let fromJoinRegex = try? NSRegularExpression(
        pattern: "(?i)\\b(?:FROM|JOIN)\\s+([A-Za-z_][A-Za-z0-9_]*)(?:\\s+(?:AS\\s+)?([A-Za-z_][A-Za-z0-9_]*))?"
    )

    private static func parseTableAliases(_ text: String) -> [String: String] {
        guard let regex = fromJoinRegex else { return [:] }
        var map: [String: String] = [:]
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let tableRange = Range(match.range(at: 1), in: text) else { continue }
            let table = String(text[tableRange])
            map[table.lowercased()] = table
            if let aliasRange = Range(match.range(at: 2), in: text) {
                let alias = String(text[aliasRange])
                if !aliasExclusions.contains(alias.uppercased()) {
                    map[alias.lowercased()] = table
                }
            }
        }
        return map
    }

    private static func rank(_ candidates: [SQLCompletionItem], partial: String) -> [SQLCompletionItem] {
        let needle = partial.lowercased()
        var seen = Set<String>()
        var prefixed: [SQLCompletionItem] = []
        var contained: [SQLCompletionItem] = []
        for item in candidates {
            let lower = item.text.lowercased()
            let matches = needle.isEmpty || lower.contains(needle)
            guard matches, seen.insert(lower).inserted else { continue }
            if needle.isEmpty || lower.hasPrefix(needle) { prefixed.append(item) }
            else { contained.append(item) }
        }
        prefixed.sort { $0.text.lowercased() < $1.text.lowercased() }
        contained.sort { $0.text.lowercased() < $1.text.lowercased() }
        return Array((prefixed + contained).prefix(resultLimit))
    }
}
