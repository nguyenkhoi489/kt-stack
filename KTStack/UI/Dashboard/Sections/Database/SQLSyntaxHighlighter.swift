import AppKit

final class SQLSyntaxHighlighter: NSObject, NSTextStorageDelegate {
    var keywords: Set<String> = []

    private let keywordColor = NSColor(editorHex: 0x0000FF)
    private let stringColor = NSColor(editorHex: 0xA31515)
    private let numberColor = NSColor(editorHex: 0x098658)
    private let commentColor = NSColor(editorHex: 0x008000)

    private static let wordPattern = try? NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]*")
    private static let numberPattern = try? NSRegularExpression(pattern: "\\b\\d+(?:\\.\\d+)?\\b")
    private static let stringPattern = try? NSRegularExpression(
        pattern: "'(?:[^'\\\\]|\\\\.)*'|\"(?:[^\"\\\\]|\\\\.)*\"|`(?:[^`]|``)*`"
    )
    private static let commentPattern = try? NSRegularExpression(
        pattern: "--[^\\n]*|/\\*[\\s\\S]*?\\*/"
    )

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range _: NSRange,
        changeInLength _: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        highlight(textStorage)
    }

    func highlight(_ storage: NSTextStorage) {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)

        applyKeywords(in: text, storage: storage, range: full)
        apply(Self.numberPattern, color: numberColor, in: text, storage: storage, range: full)
        apply(Self.stringPattern, color: stringColor, in: text, storage: storage, range: full)
        apply(Self.commentPattern, color: commentColor, in: text, storage: storage, range: full)
    }

    private func applyKeywords(in text: NSString, storage: NSTextStorage, range: NSRange) {
        guard !keywords.isEmpty else { return }
        Self.wordPattern?.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let match else { return }
            let word = text.substring(with: match.range).uppercased()
            if keywords.contains(word) {
                storage.addAttribute(.foregroundColor, value: keywordColor, range: match.range)
            }
        }
    }

    private func apply(
        _ pattern: NSRegularExpression?,
        color: NSColor,
        in text: NSString,
        storage: NSTextStorage,
        range: NSRange
    ) {
        pattern?.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

private extension NSColor {
    convenience init(editorHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
