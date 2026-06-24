import Foundation

public struct WordPressBackupInspector: Sendable {
    public init() {}

    public func inspect(_ file: URL) throws -> WordPressBackupKind {
        switch file.pathExtension.lowercased() {
        case "wpress":
            return .aioWpress
        case "zip":
            let installer = file.deletingLastPathComponent().appendingPathComponent("installer.php")
            guard FileManager.default.fileExists(atPath: installer.path) else {
                throw RestoreArchiveError.missingDuplicatorInstaller
            }
            guard try looksLikeDuplicator(file) else { throw RestoreArchiveError.notWordPressBackup }
            return .duplicatorZip
        case let other:
            throw RestoreArchiveError.unsupportedFormat(other)
        }
    }

    private func looksLikeDuplicator(_ file: URL) throws -> Bool {
        let entries = try RestoreShellTools.zipEntries(file).map { $0.lowercased() }
        let hasInstaller = entries.contains { $0.hasSuffix("installer.php") || $0.contains("dup-installer/") }
        let hasDump = entries.contains { $0.hasSuffix(".sql") || $0.hasSuffix(".sql.gz") || $0.contains("database") }
        let hasWordPress = entries.contains { $0.hasSuffix("wp-load.php") || $0.contains("wp-includes/") }
        return hasInstaller && (hasDump || hasWordPress)
    }
}
