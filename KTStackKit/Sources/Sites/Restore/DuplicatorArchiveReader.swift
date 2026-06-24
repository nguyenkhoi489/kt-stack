import Foundation

public struct DuplicatorArchiveReader: RestoreArchiveExtractor {
    public init() {}

    public func extract(_ file: URL, into staging: URL,
                        emit: @Sendable (String) -> Void) async throws -> PreparedWordPressPayload {
        try RestoreDiskPreflight.ensureSpace(forArchive: file, at: staging)

        let extracted = staging.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)

        emit("Extracting Duplicator archive…")
        try RestoreShellTools.unzip(file, into: extracted)
        try Task.checkCancellation()
        try RestoreContainment.assertNoSymlinksOrEscapes(in: extracted)

        emit("Locating database dump…")
        let rawDump = try WordPressPayloadMetadata.findDump(in: extracted)
        let dump = try normalizedDump(rawDump, into: staging)
        try WordPressPayloadMetadata.assertNoInstallerTokens(inDump: dump)

        emit("Locating WordPress web root…")
        let docroot = try WordPressPayloadMetadata.locateDocroot(in: extracted)
        WordPressPayloadMetadata.stripInstallerScaffolding(docroot: docroot)

        let tablePrefix = WordPressPayloadMetadata.derivePrefixFromDump(dump)
            ?? WordPressPayloadMetadata.readTablePrefix(docroot: docroot)
        let sourceURL = WordPressPayloadMetadata.extractSourceURL(fromDump: dump)

        return PreparedWordPressPayload(
            stagingRoot: staging,
            docroot: docroot,
            sqlDump: dump,
            tablePrefix: tablePrefix,
            sourceURL: sourceURL,
            wpVersion: nil,
            isContentOnly: false,
            kind: .duplicatorZip)
    }

    private func normalizedDump(_ dump: URL, into staging: URL) throws -> URL {
        let target = staging.appendingPathComponent("database.sql")
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        if RestoreShellTools.isGzip(dump) {
            try RestoreShellTools.gunzip(dump, to: target)
        } else {
            try FileManager.default.copyItem(at: dump, to: target)
        }
        return target
    }
}
