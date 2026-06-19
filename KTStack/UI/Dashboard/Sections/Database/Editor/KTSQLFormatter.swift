import Foundation

enum KTSQLFormatter {
    private static let clauseKeywords = [
        "FROM", "WHERE", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "JOIN",
        "GROUP BY", "ORDER BY", "HAVING", "LIMIT", "OFFSET", "UNION", "VALUES", "SET"
    ]

    static func format(_ sql: String) -> String {
        let collapsed = collapseWhitespaceOutsideQuotes(sql)
        var output = collapsed
        for keyword in clauseKeywords {
            output = insertBreak(before: keyword, in: output)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseWhitespaceOutsideQuotes(_ text: String) -> String {
        var result = ""
        var quote: Character?
        var escaped = false
        var pendingSpace = false
        for character in text {
            if let active = quote {
                result.append(character)
                if escaped { escaped = false; continue }
                if character == "\\" && active != "`" { escaped = true; continue }
                if character == active { quote = nil }
                continue
            }
            if character == "'" || character == "\"" || character == "`" {
                if pendingSpace { result.append(" "); pendingSpace = false }
                quote = character
                result.append(character)
            } else if character.isWhitespace {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace { result.append(" "); pendingSpace = false }
                result.append(character)
            }
        }
        return result
    }

    private static func insertBreak(before keyword: String, in text: String) -> String {
        let pattern = "(?<![\\w])" + NSRegularExpression.escapedPattern(for: keyword) + "(?![\\w])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let mutable = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: mutable.length)).reversed()
        for match in matches {
            guard !isInsideQuotes(text, location: match.range.location) else { continue }
            mutable.replaceCharacters(in: match.range, with: "\n" + keyword.uppercased())
        }
        return mutable as String
    }

    private static func isInsideQuotes(_ text: String, location: Int) -> Bool {
        var quote: Character?
        var escaped = false
        var index = 0
        for character in text {
            if index == location { break }
            if let active = quote {
                if escaped { escaped = false }
                else if character == "\\" && active != "`" { escaped = true }
                else if character == active { quote = nil }
            } else if character == "'" || character == "\"" || character == "`" {
                quote = character
            }
            index += 1
        }
        return quote != nil
    }
}
