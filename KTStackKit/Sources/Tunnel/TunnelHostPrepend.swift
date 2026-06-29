import Foundation

public enum TunnelHostPrepend {
    public static func content(chainingPrepend dumpPrepend: URL) -> String {
        """
        <?php
        if (!empty($_SERVER['HTTP_HOST'])) {
            $ktstackScheme = (!empty($_SERVER['HTTPS']) && strtolower($_SERVER['HTTPS']) !== 'off') ? 'https' : 'http';
            $ktstackUrl = $ktstackScheme . '://' . $_SERVER['HTTP_HOST'];
            if (!defined('WP_HOME')) { define('WP_HOME', $ktstackUrl); }
            if (!defined('WP_SITEURL')) { define('WP_SITEURL', $ktstackUrl); }
        }
        $ktstackChainedPrepend = \(phpStringLiteral(dumpPrepend.path));
        if ($ktstackChainedPrepend !== __FILE__ && is_file($ktstackChainedPrepend)) {
            require $ktstackChainedPrepend;
        }
        """
    }

    public static func write(
        to url: URL,
        chainingPrepend dumpPrepend: URL,
        fileManager: FileManager = .default
    ) throws {
        let dir = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try content(chainingPrepend: dumpPrepend).write(to: url, atomically: true, encoding: .utf8)
    }

    private static func phpStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }
}
