import Foundation

enum WordPressPayloadMetadata {
    static func findDump(in root: URL) throws -> URL {
        let fm = FileManager.default
        var candidates: [(depth: Int, url: URL)] = []
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw RestoreArchiveError.dumpNotFound
        }
        for case let url as URL in walker {
            let name = url.lastPathComponent.lowercased()
            guard name.hasSuffix(".sql") || name.hasSuffix(".sql.gz") else { continue }
            candidates.append((url.pathComponents.count, url))
        }
        let ranked = candidates.sorted { lhs, rhs in
            let lScore = score(lhs.url)
            let rScore = score(rhs.url)
            if lScore != rScore { return lScore > rScore }
            return lhs.depth < rhs.depth
        }
        guard let best = ranked.first?.url else { throw RestoreArchiveError.dumpNotFound }
        return best
    }

    private static func score(_ url: URL) -> Int {
        let name = url.lastPathComponent.lowercased()
        var value = 0
        if name.contains("database") { value += 3 }
        if name.contains("db") { value += 1 }
        if name.hasSuffix(".sql") { value += 1 }
        return value
    }

    static func locateDocroot(in root: URL) throws -> URL {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw RestoreArchiveError.docrootNotFound
        }
        var best: URL?
        var bestDepth = Int.max
        for case let url as URL in walker where url.lastPathComponent == "wp-load.php" {
            let depth = url.pathComponents.count
            if depth < bestDepth {
                bestDepth = depth
                best = url.deletingLastPathComponent()
            }
        }
        guard let docroot = best else { throw RestoreArchiveError.docrootNotFound }
        return docroot
    }

    static func readTablePrefix(docroot: URL) -> String {
        let configURL = docroot.appendingPathComponent("wp-config.php")
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else { return "wp_" }
        let pattern = #"\$table_prefix\s*=\s*['\"]([A-Za-z0-9_]+)['\"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: contents, range: NSRange(contents.startIndex..., in: contents)),
              let range = Range(match.range(at: 1), in: contents)
        else {
            return "wp_"
        }
        return String(contents[range])
    }

    private static let dumpScanBytes = 16_000_000

    static func extractSourceURL(fromDump dump: URL) -> String? {
        guard let text = readDumpHead(dump) else { return nil }
        let pattern = #"['\"](?:siteurl|home)['\"]\s*,\s*['\"](https?://[^'\"]+)['\"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[range])
    }

    static func derivePrefixFromDump(_ dump: URL) -> String? {
        guard let text = readDumpHead(dump) else { return nil }
        let pattern = #"CREATE TABLE\s+`?([A-Za-z0-9_]+?)(?:options|users)`?\s"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        let prefix = String(text[range])
        return prefix.isEmpty ? nil : prefix
    }

    static func assertNoInstallerTokens(inDump dump: URL) throws {
        guard let text = readDumpHead(dump) else { return }
        for token in ["{{SiteUrl}}", "{{HomeUrl}}", "%%SITEURL%%", "{{SITE_URL}}", "{{HOME_URL}}"] {
            if text.contains(token) { throw RestoreArchiveError.unplacedInstallerToken(token) }
        }
    }

    private static func readDumpHead(_ dump: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: dump) else { return nil }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: dumpScanBytes)
        return String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1)
    }

    static func stripInstallerScaffolding(docroot: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: docroot.path) else { return }
        for entry in entries {
            let lower = entry.lowercased()
            let isInstallerFile = lower == "installer.php"
                || lower.hasSuffix("installer.php")
                || lower.hasSuffix("installer-backup.php")
            let isDupDir = lower.hasPrefix("dup-installer")
            if isInstallerFile || isDupDir {
                try? fm.removeItem(at: docroot.appendingPathComponent(entry))
            }
        }
    }
}
