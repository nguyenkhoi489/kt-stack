import Foundation

/// One-shot, depth-1 scan of the managed sites root: lists immediate subfolders, inspects each via
/// `SiteInspector`, and flags those already registered (by canonicalized path) so a re-scan never
/// proposes a duplicate of a folder that is already a site. Pure read-only enumeration — importing is
/// the caller's explicit action (`SiteRegistry.add`), not a side effect of scanning.
public struct SiteScanner: Sendable {
    /// One scan result row. `id` is the folder path so SwiftUI selection keys on it.
    /// `proposedDomain` is the inspector's base proposal — the registry assigns the FINAL domain on
    /// import and may suffix `-2`/`-3` if that base collides, so treat this as a preview, not a promise.
    public struct ScannedSite: Identifiable, Equatable, Sendable {
        public var id: String { folder.path }
        public let folder: URL
        public let docroot: URL
        public let proposedDomain: String
        public let type: SiteType
        public let alreadyRegistered: Bool
    }

    private let inspector = SiteInspector()

    public init() {}

    /// Depth-1 scan of `root`. Skips dotfolders, symlinks, and file-system packages (e.g. `.app`),
    /// and tolerates a per-entry read failure (a permission-denied subdir is skipped, not fatal).
    /// `existingPaths` are the registered sites' folder paths (any form); they set `alreadyRegistered`
    /// after both sides are canonicalized. `tld` shapes each proposed `<name>.<tld>` domain.
    public func scan(root: URL,
                     tld: String = AppPreferences.defaultTLD,
                     existingPaths: [String] = [],
                     fileManager: FileManager = .default) -> [ScannedSite] {
        let existing = Set(existingPaths.map(Self.canonical))
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }

        return entries
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { entry -> ScannedSite? in
                guard let v = try? entry.resourceValues(forKeys: Set(keys)),
                      v.isDirectory == true, v.isSymbolicLink != true, v.isPackage != true else { return nil }
                let info = inspector.inspect(folder: entry, tld: tld, fileManager: fileManager)
                return ScannedSite(folder: entry,
                                   docroot: info.docroot,
                                   proposedDomain: info.defaultDomain,
                                   type: info.type,
                                   alreadyRegistered: existing.contains(Self.canonical(entry.path)))
            }
    }

    /// Canonical path for dedup: standardize + resolve symlinks so `/a/b`, `/a/./b`, and a symlinked
    /// path to the same docroot all compare equal.
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
