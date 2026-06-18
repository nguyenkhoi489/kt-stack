import Foundation

public struct PharProvisioner: Sendable {
    public let url: URL
    public let sha256: String
    public let dest: URL
    private let paths: AppSupportPaths

    public init(paths: AppSupportPaths, url: URL, sha256: String, dest: URL) {
        self.paths = paths
        self.url = url
        self.sha256 = sha256
        self.dest = dest
    }

    public static func wpCli(paths: AppSupportPaths) -> PharProvisioner {
        PharProvisioner(
            paths: paths,
            url: URL(string: "https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar")!,
            sha256: "ce34ddd838f7351d6759068d09793f26755463b4a4610a5a5c0a97b68220d85c",
            dest: paths.wpCliPhar)
    }

    public var isProvisioned: Bool {
        guard FileManager.default.fileExists(atPath: dest.path),
              let actual = try? ChecksumVerifier.sha256(of: dest) else { return false }
        return actual.caseInsensitiveCompare(sha256) == .orderedSame
    }

    @discardableResult
    public func provision(onProgress: @escaping @Sendable (RuntimeDownloader.Progress) -> Void = { _ in }) async throws -> URL {
        if isProvisioned { return dest }
        try paths.ensureDirectoryTree()
        let result = try await RuntimeDownloader(paths: paths)
            .downloadVerifiedFile(url: url, sha256: sha256, to: dest, onProgress: onProgress)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: result.path)
        return result
    }
}
