import Foundation

public struct ComposerProvisioner: Sendable {
    public static let version = "2.10.1"
    public static let sha256 = "345b9c6a98da5c30dcbd4b0d99fc8710bf0ae98a3898eea18f7b2ad9dec93f06"
    public static var downloadURL: URL {
        URL(string: "https://getcomposer.org/download/\(version)/composer.phar")!
    }

    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) {
        self.paths = paths
    }

    public var isProvisioned: Bool {
        guard FileManager.default.fileExists(atPath: paths.composerPhar.path),
              let actual = try? ChecksumVerifier.sha256(of: paths.composerPhar) else { return false }
        return actual.caseInsensitiveCompare(Self.sha256) == .orderedSame
    }

    @discardableResult
    public func provision(onProgress: @escaping @Sendable (RuntimeDownloader.Progress) -> Void = { _ in }) async throws -> URL {
        if isProvisioned { return paths.composerPhar }
        try paths.ensureDirectoryTree()
        let dest = try await RuntimeDownloader(paths: paths)
            .downloadVerifiedFile(
                url: Self.downloadURL,
                sha256: Self.sha256,
                to: paths.composerPhar,
                onProgress: onProgress
            )
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dest.path)
        return dest
    }
}
