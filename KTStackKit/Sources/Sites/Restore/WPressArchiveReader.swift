import Foundation

public struct WPressArchiveReader: RestoreArchiveExtractor {
    public init() {}

    private enum Layout {
        static let nameLength = 255
        static let sizeLength = 14
        static let mtimeLength = 12
        static let prefixLength = 4096
        static let headerLength = nameLength + sizeLength + mtimeLength + prefixLength
        static let nameOffset = 0
        static let sizeOffset = nameLength
        static let mtimeOffset = sizeOffset + sizeLength
        static let prefixOffset = mtimeOffset + mtimeLength
        static let chunkSize = 256 * 1024
    }

    public func extract(_ file: URL, into staging: URL,
                        emit: @Sendable (String) -> Void) async throws -> PreparedWordPressPayload {
        try RestoreDiskPreflight.ensureSpace(forArchive: file, at: staging)

        let docroot = staging.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: docroot, withIntermediateDirectories: true)

        emit("Reading .wpress archive…")
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        while true {
            try Task.checkCancellation()
            guard let header = try readHeader(handle) else { break }
            try writeEntry(header, handle: handle, into: docroot)
        }

        try RestoreContainment.assertNoSymlinksOrEscapes(in: docroot)

        emit("Locating database dump…")
        let dump = try relocateRootFile("database.sql", from: docroot, to: staging.appendingPathComponent("database.sql"))
        guard let dump else { throw RestoreArchiveError.dumpNotFound }

        let metadata = readPackageMetadata(in: docroot)
        let tablePrefix = metadata.tablePrefix ?? WordPressPayloadMetadata.readTablePrefix(docroot: docroot)
        let sourceURL = metadata.sourceURL ?? WordPressPayloadMetadata.extractSourceURL(fromDump: dump)

        return PreparedWordPressPayload(
            stagingRoot: staging,
            docroot: docroot,
            sqlDump: dump,
            tablePrefix: tablePrefix,
            sourceURL: sourceURL,
            wpVersion: metadata.wpVersion,
            isContentOnly: true,
            kind: .aioWpress)
    }

    private struct Header {
        let name: String
        let size: Int
        let prefix: String
        var relativePath: String { prefix.isEmpty ? name : prefix + "/" + name }
    }

    private func readFully(_ handle: FileHandle, _ count: Int) throws -> Data {
        var buffer = Data()
        buffer.reserveCapacity(count)
        while buffer.count < count {
            guard let chunk = try handle.read(upToCount: count - buffer.count), !chunk.isEmpty else { break }
            buffer.append(chunk)
        }
        return buffer
    }

    private func readHeader(_ handle: FileHandle) throws -> Header? {
        let block = try readFully(handle, Layout.headerLength)
        if block.isEmpty { return nil }
        guard block.count == Layout.headerLength else {
            throw RestoreArchiveError.archiveDesync("truncated header (\(block.count) of \(Layout.headerLength) bytes)")
        }

        let name = trimmedField(block, offset: Layout.nameOffset, length: Layout.nameLength)
        if name.isEmpty { return nil }

        let prefix = trimmedField(block, offset: Layout.prefixOffset, length: Layout.prefixLength)
        let sizeField = trimmedField(block, offset: Layout.sizeOffset, length: Layout.sizeLength)
        guard let size = Int(sizeField), size >= 0 else {
            throw RestoreArchiveError.archiveDesync("invalid entry size “\(sizeField)” for \(name)")
        }
        return Header(name: name, size: size, prefix: prefix)
    }

    private func writeEntry(_ header: Header, handle: FileHandle, into docroot: URL) throws {
        let target = try RestoreContainment.safeResolve(base: docroot, entryPath: header.relativePath)
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard fm.createFile(atPath: target.path, contents: nil) else {
            throw RestoreArchiveError.extractFailed("could not create \(header.relativePath)")
        }
        let out = try FileHandle(forWritingTo: target)
        defer { try? out.close() }

        var remaining = header.size
        while remaining > 0 {
            let want = min(remaining, Layout.chunkSize)
            let chunk = try readFully(handle, want)
            guard chunk.count == want else {
                throw RestoreArchiveError.archiveDesync("truncated content for \(header.relativePath) (\(chunk.count) of \(want) bytes)")
            }
            out.write(chunk)
            remaining -= want
        }
    }

    private func trimmedField(_ data: Data, offset: Int, length: Int) -> String {
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: length)
        let field = data[start..<end]
        let terminated = field.prefix { $0 != 0 }
        var slice = terminated
        while let last = slice.last, last == 0x20 { slice = slice.dropLast() }
        return String(decoding: slice, as: UTF8.self)
    }

    private func relocateRootFile(_ name: String, from docroot: URL, to target: URL) throws -> URL? {
        let fm = FileManager.default
        let source = docroot.appendingPathComponent(name)
        guard fm.fileExists(atPath: source.path) else { return nil }
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: source, to: target)
        return target
    }

    private struct PackageMetadata {
        var sourceURL: String?
        var wpVersion: String?
        var tablePrefix: String?
    }

    private func readPackageMetadata(in docroot: URL) -> PackageMetadata {
        let url = docroot.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return PackageMetadata()
        }
        func nestedString(_ path: [String]) -> String? {
            var current: Any? = object
            for key in path {
                guard let dict = current as? [String: Any] else { return nil }
                current = dict[key]
            }
            guard let value = current as? String, !value.isEmpty else { return nil }
            return value
        }
        func firstString(_ paths: [[String]]) -> String? {
            for path in paths {
                if let value = nestedString(path) { return value }
            }
            return nil
        }
        return PackageMetadata(
            sourceURL: firstString([["SiteURL"], ["HomeURL"], ["Domain"], ["URL"]]),
            wpVersion: firstString([["WordPress", "Version"], ["WordPressVersion"], ["Version"]]),
            tablePrefix: firstString([["Database", "Prefix"], ["Prefix"], ["TablePrefix"]]))
    }
}
