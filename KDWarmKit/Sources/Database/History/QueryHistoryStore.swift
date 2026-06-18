import Foundation

public final class QueryHistoryStore {
    public let limit: Int

    private let fileURL: URL
    private let fileManager: FileManager
    private var cache: [QueryHistoryEntry]

    public init(
        paths: AppSupportPaths = AppSupportPaths(),
        limit: Int = 500,
        fileManager: FileManager = .default
    ) {
        self.fileURL = paths.queryHistoryFile
        self.limit = limit
        self.fileManager = fileManager
        self.cache = []
        self.cache = Self.load(from: fileURL, fileManager: fileManager)
    }

    public func entries() -> [QueryHistoryEntry] {
        cache
    }

    public func record(sql: String, connectionLabel: String, database: String?, ranAt: Date = Date()) throws {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let first = cache.first,
           first.sql == trimmed,
           first.connectionLabel == connectionLabel,
           first.database == database {
            return
        }
        cache.insert(QueryHistoryEntry(sql: trimmed,
                                       ranAt: ranAt,
                                       connectionLabel: connectionLabel,
                                       database: database),
                     at: 0)
        if cache.count > limit {
            cache.removeLast(cache.count - limit)
        }
        try flush()
    }

    public func clear() throws {
        cache = []
        try flush()
    }

    private func flush() throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cache)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL, fileManager: FileManager) -> [QueryHistoryEntry] {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([QueryHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }
}
