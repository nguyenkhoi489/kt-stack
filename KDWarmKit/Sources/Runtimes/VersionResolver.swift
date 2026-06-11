import Foundation

/// Resolves a project's desired runtime versions from marker files (no global fallback here — the
/// caller layers the global default on top). Precedence, highest first:
///   `.kdwarmrc`  (TOML-ish: `php = "8.3"`, `node = "22"`)
///   per-language fallback: `.php-version` / `.nvmrc` / `.python-version`
///
/// `.kdwarmrc` is project-controlled = untrusted: values are returned verbatim as strings and MUST
/// be validated/clamped against the installed set by the caller before anything is executed.
public struct VersionResolver: Sendable {
    public init() {}

    /// All versions a project pins via marker files (languages with no marker are absent).
    public func versions(forProjectAt dir: URL) -> [RuntimeLanguage: String] {
        var result: [RuntimeLanguage: String] = [:]
        let rc = Self.parseKDWarmRC(readFile(dir, ".kdwarmrc"))
        for lang in RuntimeLanguage.allCases {
            if let v = rc[lang.rawValue], !v.isEmpty { result[lang] = v }
        }
        // Per-language fallbacks (only when not already set by .kdwarmrc).
        merge(&result, .php, fromFile: readFile(dir, ".php-version"))
        merge(&result, .node, fromFile: readFile(dir, ".nvmrc"))
        merge(&result, .python, fromFile: readFile(dir, ".python-version"))
        return result
    }

    public func version(_ lang: RuntimeLanguage, forProjectAt dir: URL) -> String? {
        versions(forProjectAt: dir)[lang]
    }

    /// Parse the `.kdwarmrc` key/value lines. Tolerant: `key = "value"`, `key=value`, `#` comments.
    /// Pure (no I/O) so it is unit-tested directly.
    public static func parseKDWarmRC(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty && !value.isEmpty { map[key] = value }
        }
        return map
    }

    // MARK: - Private

    private func merge(_ result: inout [RuntimeLanguage: String], _ lang: RuntimeLanguage, fromFile text: String) {
        guard result[lang] == nil else { return }
        let v = text.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        // `.nvmrc` may say `v22.1.0` / `lts/*` — strip a leading `v`; leave the rest for the clamp step.
        let cleaned = v.hasPrefix("v") ? String(v.dropFirst()) : v
        if !cleaned.isEmpty { result[lang] = cleaned }
    }

    private func readFile(_ dir: URL, _ name: String) -> String {
        (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }
}
