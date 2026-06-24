import Foundation

public struct PreparedWordPressPayload: Sendable, Equatable {
    public let stagingRoot: URL
    public let docroot: URL
    public let sqlDump: URL
    public let tablePrefix: String
    public let sourceURL: String?
    public let wpVersion: String?
    public let isContentOnly: Bool
    public let kind: WordPressBackupKind

    public init(stagingRoot: URL, docroot: URL, sqlDump: URL, tablePrefix: String,
                sourceURL: String?, wpVersion: String?, isContentOnly: Bool,
                kind: WordPressBackupKind) {
        self.stagingRoot = stagingRoot
        self.docroot = docroot
        self.sqlDump = sqlDump
        self.tablePrefix = tablePrefix
        self.sourceURL = sourceURL
        self.wpVersion = wpVersion
        self.isContentOnly = isContentOnly
        self.kind = kind
    }
}
