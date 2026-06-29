import Foundation

public struct RestoreStagingArea: Sendable {
    private let paths: AppSupportPaths

    public init(paths: AppSupportPaths) {
        self.paths = paths
    }

    @discardableResult
    public func make(id: String = UUID().uuidString) throws -> URL {
        let fm = FileManager.default
        let url = paths.restoreStaging(id: id)
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    public func discard(_ staging: URL) {
        try? FileManager.default.removeItem(at: staging)
    }

    public func sweepOrphans(keeping activeIDs: Set<String>) {
        let fm = FileManager.default
        let root = paths.restoreStagingRoot
        guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        for entry in entries where !activeIDs.contains(entry) {
            try? fm.removeItem(at: root.appendingPathComponent(entry, isDirectory: true))
        }
    }
}
