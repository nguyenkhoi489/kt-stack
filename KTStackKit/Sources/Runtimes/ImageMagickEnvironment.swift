import Foundation

public enum ImageMagickEnvironment {
    public static let bundleDirName = "imagick-magick"

    public static func directory(modulesDir: URL) -> URL {
        modulesDir.appendingPathComponent(bundleDirName, isDirectory: true)
    }

    public static func isPresent(modulesDir: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: directory(modulesDir: modulesDir).appendingPathComponent("coders", isDirectory: true).path
        )
    }

    public static func variables(modulesDir: URL) -> [String: String] {
        guard isPresent(modulesDir: modulesDir) else { return [:] }
        let root = directory(modulesDir: modulesDir)
        return [
            "MAGICK_HOME": root.path,
            "MAGICK_CODER_MODULE_PATH": root.appendingPathComponent("coders").path,
            "MAGICK_CODER_FILTER_PATH": root.appendingPathComponent("filters").path,
            "MAGICK_CONFIGURE_PATH": root.appendingPathComponent("config").path,
        ]
    }

    public static func sortedVariables(modulesDir: URL) -> [(key: String, value: String)] {
        variables(modulesDir: modulesDir).sorted { $0.key < $1.key }
    }
}
