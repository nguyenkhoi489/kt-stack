import Foundation

enum RestoreFixtureBuilder {
    static func makeTempDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-restore-tests", isDirectory: true)
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    struct WPressEntry {
        let name: String
        let prefix: String
        let content: Data
    }

    static func writeWPress(_ entries: [WPressEntry], to url: URL) throws {
        var blob = Data()
        for entry in entries {
            blob.append(field(entry.name, length: 255))
            blob.append(field(String(entry.content.count), length: 14))
            blob.append(field("0", length: 12))
            blob.append(field(entry.prefix, length: 4096))
            blob.append(entry.content)
        }
        blob.append(Data(count: 4377))
        try blob.write(to: url)
    }

    private static func field(_ value: String, length: Int) -> Data {
        var bytes = Array(value.utf8.prefix(length))
        bytes.append(contentsOf: repeatElement(0, count: length - bytes.count))
        return Data(bytes)
    }

    static func makeDuplicatorZip(to zipURL: URL, layout: [String: String]) throws {
        let staging = try makeTempDir("dup-src")
        defer { try? FileManager.default.removeItem(at: staging) }
        for (relativePath, contents) in layout {
            let file = staging.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.data(using: .utf8)!.write(to: file)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.arguments = ["-q", "-r", zipURL.path, "."]
        proc.currentDirectoryURL = staging
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
    }
}
