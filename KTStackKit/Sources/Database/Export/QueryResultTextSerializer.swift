import Foundation

public enum QueryResultTextSerializer {
    public static func csv(
        _ result: QueryResult,
        rows indices: [Int]? = nil,
        includeHeaders: Bool = true
    ) -> String {
        serialize(
            result,
            rows: indices,
            includeHeaders: includeHeaders,
            delimiter: ",",
            lineEnding: "\r\n"
        )
    }

    public static func tsv(
        _ result: QueryResult,
        rows indices: [Int]? = nil,
        includeHeaders: Bool = false
    ) -> String {
        serialize(
            result,
            rows: indices,
            includeHeaders: includeHeaders,
            delimiter: "\t",
            lineEnding: "\n"
        )
    }

    private static func serialize(
        _ result: QueryResult,
        rows indices: [Int]?,
        includeHeaders: Bool,
        delimiter: String,
        lineEnding: String
    ) -> String {
        var lines: [String] = []
        if includeHeaders {
            lines.append(
                result.columns
                    .map { escape($0.name, delimiter: delimiter) }
                    .joined(separator: delimiter)
            )
        }
        let rowIndices = indices ?? Array(result.rows.indices)
        for index in rowIndices where result.rows.indices.contains(index) {
            lines.append(
                result.rows[index]
                    .map { escape($0.displayText ?? "", delimiter: delimiter) }
                    .joined(separator: delimiter)
            )
        }
        return lines.joined(separator: lineEnding)
    }

    private static func escape(_ field: String, delimiter: String) -> String {
        let mustQuote = field.contains(delimiter) || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        guard mustQuote else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
