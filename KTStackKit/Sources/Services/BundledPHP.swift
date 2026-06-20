import Foundation

public enum BundledPHP {

    public static let defaultVersion = "8.4"

    public static let plannedVersions = ["7.4", "8.0", "8.1", "8.2", "8.3", "8.4"]

    public static func fpmBinary(for version: String, php runtimeRoot: URL) -> URL {
        runtimeRoot.appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("php-fpm")
    }

    public static func availableVersions(php runtimeRoot: URL, fileManager: FileManager = .default) -> [String] {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: runtimeRoot.path) else { return [] }
        return entries
            .filter { fileManager.isExecutableFile(atPath: fpmBinary(for: $0, php: runtimeRoot).path) }
            .sorted()
    }
}
