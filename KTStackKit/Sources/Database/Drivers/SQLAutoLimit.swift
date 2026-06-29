import Foundation

public enum SQLAutoLimit {
    public static let defaultMax = 1000

    public struct Outcome: Equatable {
        public let sql: String
        public let applied: Bool
    }

    public static func augment(_ sql: String, dialect: SQLDialect, max: Int = defaultMax) -> Outcome {
        let unchanged = Outcome(sql: sql, applied: false)
        let scan = Skeleton.scan(sql)
        guard scan.isWellFormed else { return unchanged }
        let skeleton = scan.text
        guard isSingleStatement(skeleton) else { return unchanged }
        let lead = leadingKeyword(skeleton)
        guard lead == "SELECT" || lead == "WITH" else { return unchanged }
        guard !containsWord(skeleton, "LIMIT") else { return unchanged }
        guard !containsWord(skeleton, "FETCH") else { return unchanged }
        guard !containsWord(skeleton, "OFFSET") else { return unchanged }
        guard !containsDataModification(skeleton) else { return unchanged }
        let base = strippingTrailingTerminator(sql, skeleton: skeleton)
        return Outcome(sql: dialect.paginate(base, limit: max, offset: 0), applied: true)
    }

    private static func isSingleStatement(_ skeleton: String) -> Bool {
        guard let firstSemicolon = skeleton.firstIndex(of: ";") else { return true }
        let after = skeleton[skeleton.index(after: firstSemicolon)...]
        return after.allSatisfy(\.isWhitespace)
    }

    private static func leadingKeyword(_ skeleton: String) -> String {
        let trimmed = skeleton.drop { $0.isWhitespace }
        let word = trimmed.prefix { $0.isLetter }
        return word.uppercased()
    }

    private static func containsWord(_ skeleton: String, _ word: String) -> Bool {
        skeleton.range(of: "\\b\(word)\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func containsDataModification(_ skeleton: String) -> Bool {
        ["INSERT", "UPDATE", "DELETE", "MERGE", "CREATE", "ALTER", "DROP", "TRUNCATE", "REPLACE"]
            .contains { containsWord(skeleton, $0) }
    }

    private static func strippingTrailingTerminator(_ sql: String, skeleton: String) -> String {
        var endOfContent = skeleton.endIndex
        while endOfContent > skeleton.startIndex {
            let previous = skeleton.index(before: endOfContent)
            let character = skeleton[previous]
            if character.isWhitespace || character == ";" {
                endOfContent = previous
            } else {
                break
            }
        }
        let distance = skeleton.distance(from: skeleton.startIndex, to: endOfContent)
        let cut = sql.index(sql.startIndex, offsetBy: distance)
        return String(sql[..<cut])
    }
}

private extension SQLAutoLimit {
    struct Skeleton {
        let text: String
        let isWellFormed: Bool

        static func scan(_ sql: String) -> Skeleton {
            enum Mode { case normal, single, double, backtick, lineComment, blockComment }
            var mode: Mode = .normal
            var output = ""
            output.reserveCapacity(sql.count)
            let characters = Array(sql)
            var index = 0

            func peek(_ offset: Int) -> Character? {
                let target = index + offset
                return target < characters.count ? characters[target] : nil
            }

            while index < characters.count {
                let character = characters[index]
                switch mode {
                case .normal:
                    if character == "'" { mode = .single; output.append(" ") }
                    else if character == "\"" { mode = .double; output.append(" ") }
                    else if character == "`" { mode = .backtick; output.append(" ") }
                    else if character == "-", peek(1) == "-" { mode = .lineComment; output.append("  "); index += 1 }
                    else if character == "#" { mode = .lineComment; output.append(" ") }
                    else if character == "/", peek(1) == "*" { mode = .blockComment; output.append("  "); index += 1 }
                    else { output.append(character) }
                case .single:
                    output.append(" ")
                    if character == "'" {
                        if peek(1) == "'" { output.append(" "); index += 1 } else { mode = .normal }
                    }
                case .double:
                    output.append(" ")
                    if character == "\"" {
                        if peek(1) == "\"" { output.append(" "); index += 1 } else { mode = .normal }
                    }
                case .backtick:
                    output.append(" ")
                    if character == "`" {
                        if peek(1) == "`" { output.append(" "); index += 1 } else { mode = .normal }
                    }
                case .lineComment:
                    if character == "\n" { mode = .normal; output.append(character) } else { output.append(" ") }
                case .blockComment:
                    output.append(" ")
                    if character == "*", peek(1) == "/" { output.append(" "); index += 1; mode = .normal }
                }
                index += 1
            }

            let wellFormed = (mode == .normal || mode == .lineComment)
            return Skeleton(text: output, isWellFormed: wellFormed)
        }
    }
}
