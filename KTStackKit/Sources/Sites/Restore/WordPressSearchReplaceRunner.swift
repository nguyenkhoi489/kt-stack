import Foundation

public struct WordPressSearchReplaceRunner: Sendable {
    private let cli: WordPressCLI

    public init(php: URL, phpIni: URL?, wpCliPhar: URL) {
        self.cli = WordPressCLI(php: php, phpIni: phpIni, wpCliPhar: wpCliPhar)
    }

    public func currentSiteURL(docroot: URL) -> String? {
        let value = try? cli.run(["option", "get", "siteurl", cli.pathArgument(docroot)] + WordPressCLI.skipFlags, in: docroot)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    public func run(docroot: URL, oldURL: String, newURL: String,
                    emit: @Sendable (String) -> Void) async throws {
        let newValue = try WordPressArgumentValidator.validateURL(newURL)
        let oldValue = try WordPressArgumentValidator.validateURL(oldURL)
        let path = cli.pathArgument(docroot)

        for (from, to) in replacements(old: oldValue, new: newValue) where from != to {
            try Task.checkCancellation()
            emit("Rewriting \(from) → \(to)…")
            _ = try cli.run(["search-replace", "--all-tables", "--precise", "--report-changes-only", path]
                            + WordPressCLI.skipFlags + ["--", from, to], in: docroot)
        }

        emit("Setting site address…")
        for key in ["siteurl", "home"] {
            _ = try cli.run(["option", "update", path] + WordPressCLI.skipFlags + ["--", key, newValue], in: docroot)
        }
        _ = try? cli.run(["rewrite", "flush", path] + WordPressCLI.skipFlags, in: docroot)
    }

    private func replacements(old: String, new: String) -> [(String, String)] {
        let oldHost = WordPressArgumentValidator.host(of: old)
        let newHost = WordPressArgumentValidator.host(of: new)
        return [
            ("https://\(oldHost)", new),
            ("http://\(oldHost)", new),
            (oldHost, newHost),
        ]
    }
}
