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

    /// Enforce HTTPS on a download URL before a byte is fetched. Every pinned manifest URL is already
    /// HTTPS; this hard-fails a plaintext URL so a downgrade can never reach the network (checksum
    /// pinning is the integrity backstop, transport is the first line of defense).
    static func requireHTTPS(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else {
            throw ExtractError(message: "Refusing a non-HTTPS download URL (\(url.scheme ?? "none")).")
        }
    }

    /// A redirect hop is allowed only if it stays HTTPS (used by the download delegate).
    static func isRedirectAllowed(to url: URL) -> Bool { url.scheme?.lowercased() == "https" }

    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) { self.paths = paths }

    /// Install a runtime `release`, reporting progress. Returns the installed version dir.
    @discardableResult
    public func install(_ release: RuntimeRelease,
                        onProgress: @escaping @Sendable (Progress) -> Void) async throws -> URL {
        try await installArchive(
            url: release.url, sha256: release.sha256,
            into: paths.runtimeDir(release.language.rawValue, release.version),
            markerRelPath: release.language.executableRelPath,
            onProgress: onProgress)
    }

    /// Generic on-demand install: download → checksum-verify → extract → atomically move the single
    /// top-level payload dir into `dest`, verifying the `markerRelPath` executable landed. Reused by
    /// both runtime (PHP/Node/…) and database (Redis/Postgres/MySQL) installs. Throws — leaving
    /// nothing behind — on mismatch, extract failure, missing marker, or cancellation.
    @discardableResult
    public func installArchive(url: URL, sha256: String, into dest: URL, markerRelPath: String,
                               onProgress: @escaping @Sendable (Progress) -> Void) async throws -> URL {
        try paths.ensureDirectoryTree()
        let coordinator = DownloadCoordinator { received, total in
            onProgress(Progress(received: received, total: total))
        }
        let archive = try await coordinator.download(url)
        defer { try? FileManager.default.removeItem(at: archive) }

        try Task.checkCancellation()
        try ChecksumVerifier.verify(archive, expected: sha256)
        let payload = try extract(archive)
        defer { try? FileManager.default.removeItem(at: payload.deletingLastPathComponent()) }

        // Last honored cancel point — once we move the payload into place the engine is installed.
        try Task.checkCancellation()
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: payload, to: dest)        // atomic within the same volume
        Self.stripQuarantine(dest)                    // else an ad-hoc-signed php-fpm may be Gatekeeper-blocked

        // The payload must contain the marker executable, else the install silently "succeeds" yet
        // never shows as installed. Roll back the junk dir.
        guard fm.isExecutableFile(atPath: dest.appendingPathComponent(markerRelPath).path) else {
            try? fm.removeItem(at: dest)
            throw ExtractError(message: "Archive did not contain \(markerRelPath).")
        }
        return dest
    }

    /// Install a single optional-extension `.so` into a SHARED modules dir. Distinct from
    /// `installArchive`: that one requires an executable marker (a `.so` is not +x → rejected) and
    /// replaces the whole `dest` dir (would WIPE sibling extensions). This downloads → checksum-verifies
    /// → extracts the `php-ext-<ext>/<ext>.so` artifact, then places ONLY `<soName>` into `modulesDir`,
    /// replacing just that one file and leaving every sibling `.so` intact.
    @discardableResult
    public func installSharedObject(url: URL, sha256: String, soName: String, into modulesDir: URL,
                                    onProgress: @escaping @Sendable (Progress) -> Void) async throws -> URL {
        try paths.ensureDirectoryTree()
        let coordinator = DownloadCoordinator { received, total in
            onProgress(Progress(received: received, total: total))
        }
        let archive = try await coordinator.download(url)
        defer { try? FileManager.default.removeItem(at: archive) }

        try Task.checkCancellation()
        try ChecksumVerifier.verify(archive, expected: sha256)
        let payload = try extract(archive)        // single top-level dir, e.g. imagick/
        defer { try? FileManager.default.removeItem(at: payload.deletingLastPathComponent()) }

        let fm = FileManager.default
        let src = payload.appendingPathComponent(soName)
        guard fm.fileExists(atPath: src.path) else {
            throw ExtractError(message: "Archive did not contain \(soName).")
        }
        try Task.checkCancellation()
        try fm.createDirectory(at: modulesDir, withIntermediateDirectories: true)
        let dest = modulesDir.appendingPathComponent(soName)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }   // replace THIS .so only
        try fm.moveItem(at: src, to: dest)
        Self.stripQuarantine(dest)                // ad-hoc-signed .so is quarantined by URLSession
        return dest
    }

    /// Strip `com.apple.quarantine` from a freshly-downloaded runtime tree. URLSession tags downloaded
    /// files with the quarantine xattr; for our self-built ad-hoc-signed binaries (php-fpm, redis,
    /// postgres) — unlike the notarized upstream Node/Go/Python — that attr makes Gatekeeper block the
    /// first exec. Best-effort: a missing attr or `xattr` tool is non-fatal (the binary still runs when
    /// it was never quarantined, e.g. a local-mirror install).
    private static func stripQuarantine(_ dir: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-dr", "com.apple.quarantine", dir.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
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
        try RuntimeDownloader.requireHTTPS(url)
        return try await withTaskCancellationHandler {
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

    /// Refuse any redirect that would downgrade the transport — the final hop must stay HTTPS
    /// (GitHub/CDN/MongoDB redirects are HTTPS; a redirect to http:// is dropped).
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url, RuntimeDownloader.isRedirectAllowed(to: url) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
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
