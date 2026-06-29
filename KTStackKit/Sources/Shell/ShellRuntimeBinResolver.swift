import Foundation

public struct ShellRuntimeBinResolver: Sendable {
    public enum ResolveError: Error, Equatable { case notInstalled, missingBinary }

    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) {
        self.paths = paths
    }

    public func chooseVersion(
        _ lang: RuntimeLanguage,
        cwd: URL,
        installed: [String],
        preferred: String? = nil
    ) -> String? {
        if lang == .php,
           let pinned = SiteRuntimePins(paths: paths).phpVersion(forProjectAt: cwd),
           installed.filter(ProjectVersionResolver.isValidVersion).contains(pinned)
        {
            return pinned
        }
        return ProjectVersionResolver().selectVersion(lang, forProjectAt: cwd, installed: installed, preferred: preferred)
    }

    public func confinedBinary(_ lang: RuntimeLanguage, version: String) throws -> URL {
        guard ProjectVersionResolver.isValidVersion(version) else { throw ResolveError.missingBinary }
        let binName = (lang == .php) ? "php" : lang.rawValue
        let bin = paths.runtimeBin(lang.rawValue, version)
            .appendingPathComponent(binName).standardizedFileURL
        let prefix = paths.runtimes.standardizedFileURL.path + "/"
        guard bin.path.hasPrefix(prefix), FileManager.default.isExecutableFile(atPath: bin.path) else {
            throw ResolveError.missingBinary
        }
        return bin
    }
}
