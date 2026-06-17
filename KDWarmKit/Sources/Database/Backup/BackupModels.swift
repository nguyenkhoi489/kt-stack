import Foundation

public enum RestoreTarget: Sendable, Equatable {
    case overwrite
    case newDatabase(String)
}

public struct BackupSet: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let kind: DatabaseKind
    public let engineVersion: String?
    public let profileName: String
    public let host: String
    public let databases: [String]
    public let createdAt: Date
    public var sizeBytes: Int64

    public init(
        id: UUID = UUID(),
        kind: DatabaseKind,
        engineVersion: String?,
        profileName: String,
        host: String,
        databases: [String],
        createdAt: Date = Date(),
        sizeBytes: Int64 = 0
    ) {
        self.id = id
        self.kind = kind
        self.engineVersion = engineVersion
        self.profileName = profileName
        self.host = host
        self.databases = databases
        self.createdAt = createdAt
        self.sizeBytes = sizeBytes
    }
}
