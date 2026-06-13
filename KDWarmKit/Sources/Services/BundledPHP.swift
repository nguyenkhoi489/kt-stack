import Foundation

/// PHP version policy + runtime discovery. Maps a version string to its `php-fpm` binary in the
/// runtimes layout and reports which versions are actually installed under `runtimes/php/`.
///
/// No PHP ships in the app — every version installs on demand (static-php-cli build, downloaded into
/// `runtimes/php/<version>/bin/{php,php-fpm}`). `availableVersions` honestly reports which are present
/// on disk, so the per-site picker offers only runnable versions. (Name kept for source stability.)
public enum BundledPHP {
    /// The recommended default version a new site targets (NOT physically bundled — installed on demand).
    public static let defaultVersion = "8.4"

    /// Versions the project offers for download. Used to label/sort the picker + validate input.
    public static let plannedVersions = ["7.4", "8.1", "8.3", "8.4"]

    /// `php-fpm` binary for `version` under the PHP runtimes root (`runtimes/php`).
    public static func fpmBinary(for version: String, php runtimeRoot: URL) -> URL {
        runtimeRoot.appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("php-fpm")
    }

    /// Versions whose `php-fpm` binary actually exists under `runtimes/php/<version>/bin`, sorted.
    public static func availableVersions(php runtimeRoot: URL, fileManager: FileManager = .default) -> [String] {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: runtimeRoot.path) else { return [] }
        return entries
            .filter { fileManager.isExecutableFile(atPath: fpmBinary(for: $0, php: runtimeRoot).path) }
            .sorted()
    }
}
