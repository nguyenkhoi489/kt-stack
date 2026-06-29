import Foundation

public struct WordPressReconcileResult: Sendable, Equatable {
    public let coreVersion: String?
    public let requestedVersion: String?
    public let usedLatestFallback: Bool

    public init(coreVersion: String?, requestedVersion: String?, usedLatestFallback: Bool) {
        self.coreVersion = coreVersion
        self.requestedVersion = requestedVersion
        self.usedLatestFallback = usedLatestFallback
    }
}

public struct WordPressCoreReconciler: Sendable {
    private let cli: WordPressCLI

    public init(php: URL, phpIni: URL?, wpCliPhar: URL) {
        cli = WordPressCLI(php: php, phpIni: phpIni, wpCliPhar: wpCliPhar)
    }

    public func reconcile(
        payload: PreparedWordPressPayload,
        targetDocroot: URL,
        emit: @Sendable (String) -> Void
    ) async throws -> WordPressReconcileResult {
        try FileManager.default.createDirectory(at: targetDocroot, withIntermediateDirectories: true)

        guard payload.isContentOnly else {
            emit("Moving WordPress files…")
            try moveTree(from: payload.docroot, into: targetDocroot)
            return WordPressReconcileResult(coreVersion: nil, requestedVersion: nil, usedLatestFallback: false)
        }

        let result = try downloadCore(version: payload.wpVersion, into: targetDocroot, emit: emit)
        try Task.checkCancellation()
        emit("Restoring wp-content…")
        try overlayContent(from: payload.docroot, into: targetDocroot)
        return result
    }

    private func downloadCore(
        version: String?,
        into docroot: URL,
        emit: @Sendable (String) -> Void
    ) throws -> WordPressReconcileResult {
        let base = ["core", "download", cli.pathArgument(docroot), "--force"] + WordPressCLI.skipFlags
        if let version, isPlausibleVersion(version) {
            do {
                emit("Downloading WordPress \(version)…")
                _ = try cli.run(base + ["--version=\(version)"], in: docroot)
                return WordPressReconcileResult(coreVersion: version, requestedVersion: version, usedLatestFallback: false)
            } catch {
                emit("WordPress \(version) is unavailable — downloading the latest stable release instead…")
            }
        } else {
            emit("Downloading the latest WordPress release…")
        }
        _ = try cli.run(base, in: docroot)
        return WordPressReconcileResult(coreVersion: nil, requestedVersion: version, usedLatestFallback: version != nil)
    }

    private func overlayContent(from source: URL, into target: URL) throws {
        let fm = FileManager.default
        let sourceContent = source.appendingPathComponent("wp-content", isDirectory: true)
        guard fm.fileExists(atPath: sourceContent.path) else { return }
        let targetContent = target.appendingPathComponent("wp-content", isDirectory: true)
        if fm.fileExists(atPath: targetContent.path) { try fm.removeItem(at: targetContent) }
        try fm.moveItem(at: sourceContent, to: targetContent)
    }

    private func moveTree(from source: URL, into target: URL) throws {
        let fm = FileManager.default
        for entry in try fm.contentsOfDirectory(atPath: source.path) {
            let destination = target.appendingPathComponent(entry)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: source.appendingPathComponent(entry), to: destination)
        }
    }

    private func isPlausibleVersion(_ value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"^[0-9]+\.[0-9]+(\.[0-9]+)?$"#) else { return false }
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
}
