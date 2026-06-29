import Foundation

public struct WPConfigWriter: Sendable {
    private let cli: WordPressCLI

    public init(php: URL, phpIni: URL?, wpCliPhar: URL) {
        cli = WordPressCLI(php: php, phpIni: phpIni, wpCliPhar: wpCliPhar)
    }

    public func write(
        into docroot: URL,
        database: String,
        tablePrefix: String,
        emit: @Sendable (String) -> Void
    ) throws {
        let prefix = try WordPressArgumentValidator.validateTablePrefix(tablePrefix)
        let name = try WordPressArgumentValidator.validateDatabaseName(database)

        emit("Writing wp-config.php…")
        let configArgs = [
            "config",
            "create",
            cli.pathArgument(docroot),
            "--dbname=\(name)",
            "--dbuser=root",
            "--dbpass=",
            "--dbhost=127.0.0.1",
            "--dbprefix=\(prefix)",
            "--skip-check",
            "--force",
        ] + WordPressCLI.skipFlags
        do {
            _ = try cli.run(configArgs, in: docroot)
        } catch {
            try writeTemplate(into: docroot, database: name, prefix: prefix)
            return
        }
        _ = try? cli.run(["config", "shuffle-salts", cli.pathArgument(docroot)] + WordPressCLI.skipFlags, in: docroot)
        _ = try? cli.run([
            "config",
            "set",
            "DISABLE_WP_CRON",
            "true",
            "--raw",
            "--type=constant",
            cli.pathArgument(docroot),
        ] + WordPressCLI.skipFlags, in: docroot)
    }

    private func writeTemplate(into docroot: URL, database: String, prefix: String) throws {
        let keys = [
            "AUTH_KEY",
            "SECURE_AUTH_KEY",
            "LOGGED_IN_KEY",
            "NONCE_KEY",
            "AUTH_SALT",
            "SECURE_AUTH_SALT",
            "LOGGED_IN_SALT",
            "NONCE_SALT",
        ]
        let saltLines = keys.map { "define('\($0)', '\(randomSalt())');" }.joined(separator: "\n")
        let config = """
        <?php
        define('DB_NAME', '\(database)');
        define('DB_USER', 'root');
        define('DB_PASSWORD', '');
        define('DB_HOST', '127.0.0.1');
        define('DB_CHARSET', 'utf8mb4');
        define('DB_COLLATE', '');
        \(saltLines)
        define('DISABLE_WP_CRON', true);
        $table_prefix = '\(prefix)';
        if (!defined('ABSPATH')) { define('ABSPATH', __DIR__ . '/'); }
        require_once ABSPATH . 'wp-settings.php';
        """
        try config.data(using: .utf8)!.write(to: docroot.appendingPathComponent("wp-config.php"))
    }

    private func randomSalt() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_[]{}")
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { characters[Int($0) % characters.count] })
    }
}
