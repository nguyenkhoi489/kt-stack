import Foundation

public struct WordPressInstaller: SiteInstaller {
    private let php: URL
    private let wpCliPhar: URL

    public init(php: URL, wpCliPhar: URL) {
        self.php = php
        self.wpCliPhar = wpCliPhar
    }

    public func scaffold(into folder: URL, request: NewSiteRequest,
                         emit: @Sendable (String) -> Void) async throws {
        let runner = InstallCommandRunner(php: php)
        let path = "--path=\(folder.path)"
        let database = request.databaseName ?? request.name

        emit("Downloading WordPress core…")
        _ = try runner.runPHP([wpCliPhar.path, "core", "download", path], cwd: folder)

        emit("Writing wp-config.php…")
        _ = try runner.runPHP([wpCliPhar.path, "config", "create", path,
                               "--dbname=\(database)", "--dbuser=root", "--dbpass=",
                               "--dbhost=127.0.0.1", "--skip-check"], cwd: folder)

        emit("Installing WordPress…")
        _ = try runner.runPHP(Self.coreInstallArgs(phar: wpCliPhar.path, path: path, request: request),
                              cwd: folder, stdin: request.adminPassword + "\n")
    }

    public static func coreInstallArgs(phar: String, path: String, request: NewSiteRequest) -> [String] {
        [phar, "core", "install", path,
         "--url=https://\(request.domain)",
         "--title=\(request.siteTitle)",
         "--admin_user=\(request.adminUser)",
         "--admin_email=\(request.adminEmail)",
         "--prompt=admin_password"]
    }
}
