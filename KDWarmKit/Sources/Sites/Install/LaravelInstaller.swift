import Foundation

public struct LaravelInstaller: SiteInstaller {
    private let php: URL
    private let composerPhar: URL

    public init(php: URL, composerPhar: URL) {
        self.php = php
        self.composerPhar = composerPhar
    }

    public func scaffold(into folder: URL, request: NewSiteRequest,
                         emit: @Sendable (String) -> Void) async throws {
        let runner = InstallCommandRunner(php: php)
        let parent = folder.deletingLastPathComponent()

        emit("Creating Laravel project (composer)…")
        _ = try runner.runPHP([composerPhar.path, "create-project", "laravel/laravel",
                               request.name, "--no-interaction"], cwd: parent)

        emit("Configuring .env…")
        try Self.configureEnv(in: folder, request: request)

        emit("Generating application key…")
        _ = try runner.runPHP([folder.appendingPathComponent("artisan").path,
                               "key:generate", "--force"], cwd: folder)
    }

    struct EnvMissing: LocalizedError {
        var errorDescription: String? { "composer create-project did not produce a .env file." }
    }

    static func configureEnv(in folder: URL, request: NewSiteRequest) throws {
        let env = folder.appendingPathComponent(".env")
        guard let original = try? String(contentsOf: env, encoding: .utf8) else { throw EnvMissing() }
        let replacements: [String: String] = [
            "DB_CONNECTION": "mysql",
            "DB_HOST": "127.0.0.1",
            "DB_PORT": "3306",
            "DB_DATABASE": request.databaseName ?? request.name,
            "DB_USERNAME": "root",
            "DB_PASSWORD": "",
            "APP_URL": "https://\(request.domain)",
        ]
        var lines = original.components(separatedBy: "\n")
        var seen = Set<String>()
        for index in lines.indices {
            let line = lines[index]
            guard let eq = line.firstIndex(of: "="), !line.hasPrefix("#") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            if let value = replacements[key] {
                lines[index] = "\(key)=\(value)"
                seen.insert(key)
            }
        }
        for (key, value) in replacements where !seen.contains(key) {
            lines.append("\(key)=\(value)")
        }
        try lines.joined(separator: "\n").data(using: .utf8)!.write(to: env, options: .atomic)
    }
}
