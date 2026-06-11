import Foundation

/// Downloads → verifies → extracts → atomically installs a runtime release into the runtimes layout.
///
/// Pipeline: stream the official archive to a temp file with determinate progress (design §5.8) →
/// `ChecksumVerifier` (reject + clean up on mismatch, so no partial/unverified runtime survives) →
/// `tar` extract to a temp dir → atomically move the single top-level payload dir into
/// `runtimes/<lang>/<version>/`. Cancellable (cancelling the enclosing Task cancels the transfer).
public struct RuntimeDownloader: Sendable {
    public struct Progress: Sendable {
        public let received: Int64
        public let total: Int64        // -1 when the server omits Content-Length
        public var fraction: Double { total > 0 ? min(1, Double(received) / Double(total)) : 0 }
    }

    public struct ExtractError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) { self.paths = paths }

    /// Install `release`, reporting progress. Returns the installed version dir on success; throws
    /// (leaving nothing behind) on checksum mismatch, extract failure, or cancellation.
    @discardableResult
    public func install(_ release: RuntimeRelease,
                        onProgress: @escaping @Sendable (Progress) -> Void) async throws -> URL {
        try paths.ensureDirectoryTree()
        let coordinator = DownloadCoordinator { received, total in
            onProgress(Progress(received: received, total: total))
        }
        let archive = try await coordinator.download(release.url)
        defer { try? FileManager.default.removeItem(at: archive) }

        try ChecksumVerifier.verify(archive, expected: release.sha256)
        let payload = try extract(archive)
        defer { try? FileManager.default.removeItem(at: payload.deletingLastPathComponent()) }

        let dest = paths.runtimeDir(release.language.rawValue, release.version)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: payload, to: dest)        // atomic within the same volume

        // Sanity-check the payload actually contains the language's marker executable; otherwise the
        // install would silently "succeed" yet never show as installed. Roll back the junk dir.
        let marker = dest.appendingPathComponent(release.language.executableRelPath)
        guard fm.isExecutableFile(atPath: marker.path) else {
            try? fm.removeItem(at: dest)
            throw ExtractError(message: "Archive did not contain \(release.language.executableRelPath).")
        }
        return dest
    }

    /// Untar into a fresh temp dir and return the single top-level payload directory (each official
    /// archive wraps its content in one dir — `go/`, `node-v…/`, `python/`).
    private func extract(_ archive: URL) throws -> URL {
        let work = paths.runtimes.appendingPathComponent(".dl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xf", archive.path, "-C", work.path]
        let err = Pipe(); tar.standardError = err; tar.standardOutput = FileHandle.nullDevice
        try tar.run(); tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "tar failed"
            throw ExtractError(message: "Extract failed: \(msg)")
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: work.path)
            .filter { !$0.hasPrefix(".") }
        guard entries.count == 1 else {
            throw ExtractError(message: "Unexpected archive layout (\(entries.count) top-level entries).")
        }
        return work.appendingPathComponent(entries[0], isDirectory: true)
    }
}

/// Bridges `URLSessionDownloadTask` (delegate-based progress) into async/await with cancellation.
private final class DownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var saved: URL?
    private var saveError: Error?

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    func download(_ url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                continuation = cont
                let t = session.downloadTask(with: url)
                task = t
                t.resume()
            }
        } onCancel: { [task] in task?.cancel() }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData _: Int64, totalBytesWritten written: Int64,
                    totalBytesExpectedToWrite expected: Int64) {
        onProgress(written, expected)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is deleted when this delegate returns — move it out synchronously now.
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("kdwarm-dl-\(UUID().uuidString)")
        do { try FileManager.default.moveItem(at: location, to: dest); saved = dest }
        catch { saveError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { continuation = nil; session.finishTasksAndInvalidate() }
        if let error { continuation?.resume(throwing: error); return }
        if let saved { continuation?.resume(returning: saved); return }
        continuation?.resume(throwing: saveError ?? RuntimeDownloader.ExtractError(
            message: "Download finished but the file could not be saved."))
    }
}
