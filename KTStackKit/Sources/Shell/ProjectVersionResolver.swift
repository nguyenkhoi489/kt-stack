import Foundation

public struct ProjectVersionResolver: Sendable {
    private let base = VersionResolver()
    private let homeOverride: URL?

    public init(homeOverride: URL? = nil) {
        self.homeOverride = homeOverride
    }

    public static func isValidVersion(_ value: String) -> Bool {
        value.range(of: "^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", options: .regularExpression) != nil
    }

    public static func majorMinor(fromConstraint constraint: String) -> String? {
        guard let range = constraint.range(of: "[0-9]+\\.[0-9]+", options: .regularExpression) else { return nil }
        return String(constraint[range])
    }

    public static func highest(_ versions: [String]) -> String? {
        versions.filter(isValidVersion).max { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    public static func nearest(to target: String, installed: [String]) -> (version: String, exact: Bool)? {
        let valid = installed.filter(isValidVersion)
        guard !valid.isEmpty else { return nil }
        if valid.contains(target) { return (target, true) }
        guard isValidVersion(target) else { return highest(valid).map { ($0, false) } }
        func ordinal(_ value: String) -> Int {
            let parts = value.split(separator: ".")
            let major = Int(parts.first ?? "0") ?? 0
            let minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            return major * 100 + minor
        }
        let goal = ordinal(target)
        let best = valid.min { abs(ordinal($0) - goal) < abs(ordinal($1) - goal) }
        return best.map { ($0, false) }
    }

    public func selectVersion(
        _ lang: RuntimeLanguage,
        forProjectAt cwd: URL,
        installed: [String],
        preferred: String? = nil
    ) -> String? {
        let valid = installed.filter(Self.isValidVersion)
        if let marker = resolve(lang, forProjectAt: cwd), valid.contains(marker) { return marker }
        if let preferred, valid.contains(preferred) { return preferred }
        return Self.highest(valid)
    }

    public func resolve(_ lang: RuntimeLanguage, forProjectAt start: URL, walkUp: Bool = true) -> String? {
        let home = (homeOverride ?? FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
        var dir = start.standardizedFileURL
        while true {
            if let marker = base.version(lang, forProjectAt: dir), Self.isValidVersion(marker) {
                return marker
            }
            if lang == .php, let composer = composerPHP(in: dir), Self.isValidVersion(composer) {
                return composer
            }
            if !walkUp || dir.path == home.path { return nil }
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }

    private func composerPHP(in dir: URL) -> String? {
        let url = dir.appendingPathComponent("composer.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let config = json["config"] as? [String: Any],
           let platform = config["platform"] as? [String: Any],
           let php = platform["php"] as? String,
           let resolved = Self.majorMinor(fromConstraint: php) { return resolved }
        if let require = json["require"] as? [String: Any],
           let php = require["php"] as? String,
           let resolved = Self.majorMinor(fromConstraint: php) { return resolved }
        return nil
    }
}
