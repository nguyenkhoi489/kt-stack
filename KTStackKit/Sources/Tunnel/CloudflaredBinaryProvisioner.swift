import Foundation

public struct CloudflaredRelease: Sendable {
    public let version: String
    public let arm64SHA256: String
    public let x86_64SHA256: String
    public let upstreamProvenanceURL: String

    public var sha256ForCurrentArch: String {
        ServiceBinaryCatalog.arch == "arm64" ? arm64SHA256 : x86_64SHA256
    }

    public var downloadURL: URL {
        ServiceBinaryCatalog.releaseBaseURL
            .appendingPathComponent("cloudflared-\(version)-\(ServiceBinaryCatalog.arch).tar.gz")
    }
}

public actor CloudflaredBinaryProvisioner {
    public static let release = CloudflaredRelease(
        version: "2026.6.0",
        arm64SHA256: "c43b115549b79780221a45299610c8c8ef99aa99af0cc5aae76e6fb31809dde6",
        x86_64SHA256: "6cccb8cf85417dbfdb96e11d3267cbf0cfe833790b87d17a5f7d1d537fddb554",
        upstreamProvenanceURL: "https://github.com/cloudflare/cloudflared/releases/tag/2026.6.0"
    )

    private let paths: AppSupportPaths
    private let downloader: RuntimeDownloader
    private var inFlight: Task<URL, Error>?

    public init(paths: AppSupportPaths) {
        self.paths = paths
        downloader = RuntimeDownloader(paths: paths)
    }

    public var binaryURL: URL {
        paths.toolVersionDir("cloudflared", Self.release.version)
            .appendingPathComponent("cloudflared")
    }

    public func installedBinary() -> URL? {
        let url = binaryURL
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    public func isInstalled() -> Bool {
        installedBinary() != nil
    }

    @discardableResult
    public func ensureInstalled(
        onProgress: @escaping @Sendable (RuntimeDownloader.Progress) -> Void
    ) async throws -> URL {
        if let installed = installedBinary() { return installed }
        if let inFlight { return try await inFlight.value }

        let task = Task { try await self.performInstall(onProgress: onProgress) }
        inFlight = task
        defer { if inFlight == task { inFlight = nil } }
        return try await task.value
    }

    public func cancel() {
        inFlight?.cancel()
        inFlight = nil
    }

    private func performInstall(
        onProgress: @escaping @Sendable (RuntimeDownloader.Progress) -> Void
    ) async throws -> URL {
        let dest = paths.toolVersionDir("cloudflared", Self.release.version)
        try await downloader.installArchive(
            url: Self.release.downloadURL,
            sha256: Self.release.sha256ForCurrentArch,
            into: dest,
            markerRelPath: "cloudflared",
            onProgress: onProgress
        )
        return dest.appendingPathComponent("cloudflared")
    }
}
