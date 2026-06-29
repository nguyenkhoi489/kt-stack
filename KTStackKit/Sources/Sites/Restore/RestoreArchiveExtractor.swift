import Foundation

public protocol RestoreArchiveExtractor: Sendable {
    func extract(
        _ file: URL,
        into staging: URL,
        emit: @Sendable (String) -> Void
    ) async throws -> PreparedWordPressPayload
}

public enum RestoreArchiveError: LocalizedError, Equatable {
    case unsupportedFormat(String)
    case notWordPressBackup
    case missingDuplicatorInstaller
    case pathEscape(String)
    case symlinkRejected(String)
    case dumpNotFound
    case docrootNotFound
    case insufficientDiskSpace(required: Int64, available: Int64)
    case archiveDesync(String)
    case unplacedInstallerToken(String)
    case extractFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(ext):
            "Unsupported backup format “.\(ext)”. Use a Duplicator .zip or All-in-One WP Migration .wpress file."
        case .notWordPressBackup:
            "This archive does not look like a supported WordPress backup."
        case .missingDuplicatorInstaller:
            "A Duplicator backup needs its installer.php in the same folder as the .zip archive."
        case let .pathEscape(entry):
            "Refused archive entry that escapes the extraction directory: \(entry)"
        case let .symlinkRejected(entry):
            "Refused symbolic link inside the backup archive: \(entry)"
        case .dumpNotFound:
            "Could not locate the database dump (database.sql) inside the backup."
        case .docrootNotFound:
            "Could not locate the WordPress web root inside the backup."
        case let .insufficientDiskSpace(required, available):
            "Not enough free disk space to restore. Need about \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), have \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))."
        case let .archiveDesync(detail):
            "The backup archive is corrupt or uses an unexpected layout: \(detail)"
        case let .unplacedInstallerToken(token):
            "The database dump still contains a Duplicator installer placeholder (\(token)). Re-export the backup or run the installer first."
        case let .extractFailed(detail):
            "Failed to extract the backup archive: \(detail)"
        }
    }
}

enum RestoreContainment {
    static func safeResolve(base: URL, entryPath: String) throws -> URL {
        if entryPath.hasPrefix("/") { throw RestoreArchiveError.pathEscape(entryPath) }
        let components = entryPath.split(separator: "/", omittingEmptySubsequences: true)
        if components.contains("..") { throw RestoreArchiveError.pathEscape(entryPath) }
        let resolved = base.appendingPathComponent(entryPath).standardizedFileURL
        let basePath = base.standardizedFileURL.path
        guard resolved.path == basePath || resolved.path.hasPrefix(basePath + "/") else {
            throw RestoreArchiveError.pathEscape(entryPath)
        }
        return resolved
    }

    static func assertNoSymlinksOrEscapes(in root: URL) throws {
        let fm = FileManager.default
        let basePath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard let walker = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { return }
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw RestoreArchiveError.symlinkRejected(url.lastPathComponent)
            }
            let realPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard realPath == basePath || realPath.hasPrefix(basePath + "/") else {
                throw RestoreArchiveError.pathEscape(url.path)
            }
        }
    }
}

enum RestoreDiskPreflight {
    static func ensureSpace(forArchive archive: URL, multiplier: Double = 2.5, at volume: URL) throws {
        let fm = FileManager.default
        let archiveSize = ((try? fm.attributesOfItem(atPath: archive.path))?[.size] as? NSNumber)?.int64Value ?? 0
        guard archiveSize > 0 else { return }
        let required = Int64(Double(archiveSize) * multiplier)
        let values = try volume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? Int64.max
        if available < required {
            throw RestoreArchiveError.insufficientDiskSpace(required: required, available: available)
        }
    }
}
