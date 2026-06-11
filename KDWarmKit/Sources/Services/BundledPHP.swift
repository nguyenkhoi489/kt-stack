import Foundation

/// Maps a PHP version string to its `php-fpm` binary inside the runtimes layout and discovers which
/// versions are actually installed under `runtimes/php/`.
///
/// Each PHP version is a self-contained static build (static-php-cli) installed at
/// `runtimes/php/<version>/bin/{php,php-fpm}`. The MVP intends to bundle four versions
/// (7.4/8.1/8.3/8.4); `availableVersions` honestly reports which are present on disk, so the
/// per-site version picker offers only runnable versions.
public enum BundledPHP {
    /// The version shipped bundled (staged on first run from the app's Resources).
    public static let defaultVersion = "8.4"

    /// All versions the MVP intends to bundle. Used to label/sort the picker + validate input.
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
