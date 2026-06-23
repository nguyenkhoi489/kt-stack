import Foundation

public struct WordPressSiteProbe: Sendable {
    private static let markers = ["wp-config.php", "wp-load.php", "wp-settings.php"]

    public init() {}

    public func isWordPress(siteAt folder: URL, docroot: URL? = nil,
                            fileManager: FileManager = .default) -> Bool {
        var directories = [folder]
        if let docroot, docroot.standardizedFileURL != folder.standardizedFileURL {
            directories.append(docroot)
        }
        return directories.contains { directory in
            Self.markers.contains { marker in
                fileManager.fileExists(atPath: directory.appendingPathComponent(marker).path)
            }
        }
    }
}
