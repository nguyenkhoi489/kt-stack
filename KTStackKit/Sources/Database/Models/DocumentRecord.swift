import Foundation

public struct DocumentRecord: Sendable, Equatable, Identifiable {
    public let id: String
    public let json: String
    public let identifierJSON: String?

    public init(id: String, json: String, identifierJSON: String?) {
        self.id = id
        self.json = json
        self.identifierJSON = identifierJSON
    }
}

public struct CollectionInfo: Sendable, Equatable, Identifiable {
    public var id: String {
        name
    }

    public let name: String

    public init(name: String) {
        self.name = name
    }
}
