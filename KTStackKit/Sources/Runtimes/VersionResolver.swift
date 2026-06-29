import Foundation

public struct VersionResolver: Sendable {
    public init() {}

    public func versions(forProjectAt dir: URL) -> [RuntimeLanguage: String] {
        var result: [RuntimeLanguage: String] = [:]
        let primaryRC = readFile(dir, ".ktstackrc")
        let rc = Self.parseKTStackRC(primaryRC.isEmpty ? readFile(dir, ".kdwarmrc") : primaryRC)
        for lang in RuntimeLanguage.allCases {
            if let v = rc[lang.rawValue], !v.isEmpty { result[lang] = v }
        }

        merge(&result, .php, fromFile: readFile(dir, ".php-version"))
        merge(&result, .node, fromFile: readFile(dir, ".nvmrc"))
        return result
    }

    public func version(_ lang: RuntimeLanguage, forProjectAt dir: URL) -> String? {
        versions(forProjectAt: dir)[lang]
    }

    public static func parseKTStackRC(_ text: String) -> [String: String] {
        var map: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty, !value.isEmpty { map[key] = value }
        }
        return map
    }

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
