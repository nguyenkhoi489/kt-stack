import Foundation

public struct SiteScanner: Sendable {
    public struct ScannedSite: Identifiable, Equatable, Sendable {
        public var id: String {
            folder.path
        }

        public let folder: URL
        public let docroot: URL
        public let proposedDomain: String
        public let type: SiteType
        public let alreadyRegistered: Bool
    }

    private let inspector = SiteInspector()

    public init() {}

    public func scan(
        root: URL,
        tld: String = AppPreferences.defaultTLD,
        existingPaths: [String] = [],
        fileManager: FileManager = .default
    ) -> [ScannedSite] {
        let existing = Set(existingPaths.map(Self.canonical))
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { entry -> ScannedSite? in
                guard let v = try? entry.resourceValues(forKeys: Set(keys)),
                      v.isDirectory == true, v.isSymbolicLink != true, v.isPackage != true else { return nil }
                let info = inspector.inspect(folder: entry, tld: tld, fileManager: fileManager)
                return ScannedSite(
                    folder: entry,
                    docroot: info.docroot,
                    proposedDomain: info.defaultDomain,
                    type: info.type,
                    alreadyRegistered: existing.contains(Self.canonical(entry.path))
                )
            }
    }

    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
