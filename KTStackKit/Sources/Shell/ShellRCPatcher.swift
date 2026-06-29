import CryptoKit
import Foundation

struct ShellRCPatcher {
    static let startPrefix = "# >>> KTStack PATH (managed"
    static let endMarker = "# <<< KTStack PATH (managed) <<<"

    let exportLine: String

    enum RCError: LocalizedError {
        case tampered(String)
        case duplicated(String)
        var errorDescription: String? {
            switch self {
            case let .tampered(file):
                "KTStack PATH block in \(file) was edited by hand — fix or remove it manually, then re-apply."
            case let .duplicated(file):
                "Multiple KTStack PATH blocks found in \(file) — remove the extras manually."
            }
        }
    }

    func bodyHash() -> String {
        let digest = SHA256.hash(data: Data(exportLine.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(12))
    }

    func renderedBlock() -> String {
        "\(Self.startPrefix) v1 \(bodyHash())) >>>\n\(exportLine)\n\(Self.endMarker)"
    }

    private func locateBlock(in lines: [String], file: String) throws -> Range<Int>? {
        let starts = lines.indices.filter { lines[$0].hasPrefix(Self.startPrefix) }
        guard !starts.isEmpty else { return nil }
        guard starts.count == 1 else { throw RCError.duplicated(file) }
        let start = starts[0]
        guard let end = lines[start...].firstIndex(where: { $0 == Self.endMarker }) else {
            throw RCError.tampered(file)
        }
        let body = lines[(start + 1)..<end].joined(separator: "\n")
        let header = lines[start]
        let embedded = String(header.dropFirst("\(Self.startPrefix) v1 ".count).prefix(12))
        let actual = SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12)
        guard embedded == String(actual) else { throw RCError.tampered(file) }
        return start..<(end + 1)
    }

    func contentRemovingBlock(from content: String, file: String) throws -> String {
        var lines = content.components(separatedBy: "\n")
        guard let range = try locateBlock(in: lines, file: file) else { return content }
        lines.removeSubrange(range)
        return lines.joined(separator: "\n")
    }

    func contentWithBlock(in content: String, file: String) throws -> String {
        let withoutBlock = try contentRemovingBlock(from: content, file: file)
        let trimmed = withoutBlock.hasSuffix("\n") ? String(withoutBlock.dropLast()) : withoutBlock
        let base = trimmed.isEmpty ? "" : trimmed + "\n"
        return base + renderedBlock() + "\n"
    }

    func containsValidBlock(in content: String, file: String) -> Bool {
        guard (try? locateBlock(in: content.components(separatedBy: "\n"), file: file)) != nil else { return false }
        return true
    }
}
