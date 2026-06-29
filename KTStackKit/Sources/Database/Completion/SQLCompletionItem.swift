import Foundation

public struct SQLCompletionItem: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case keyword
        case table
        case column
    }

    public let text: String
    public let kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }
}
