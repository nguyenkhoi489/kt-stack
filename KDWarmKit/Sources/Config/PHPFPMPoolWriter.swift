import Foundation

/// Renders a php-fpm configuration: one `[global]` section plus a single pool that
/// listens on a UNIX socket under `run/`. Socket-per-pool keeps pools isolated, which is
/// what Phase 3 generalises into per-PHP-version pools.
///
/// JIT note (Phase 9): the bundled PHP is compiled WITH opcache, so PHP's JIT is available.
/// Enabling `opcache.jit` in a NOTARIZED build will require the
/// `com.apple.security.cs.allow-jit` entitlement. This dev build is un-notarized, so JIT is
/// left at its default (off) here and the entitlement is recorded for Phase 9 rather than
/// exercised now.
public struct PHPFPMPoolWriter {
    public init() {}

    /// A complete php-fpm config (global + one pool). `daemonize = no` because the master
    /// runs in the foreground under launchd supervision (`php-fpm -F`).
    public func poolConfig(paths: AppSupportPaths,
                           poolName: String,
                           user: String = NSUserName()) -> String {
        let socket = paths.phpFpmSocket(poolName).path
        let log = paths.phpFpmLog(poolName).path
        // Route PHP mail() into the bundled Mailpit (SMTP sink on :1025) so dev mail is caught and
        // readable in-app. PHP appends `-t -i`; mailpit's sendmail mode reads the message on stdin.
        // The path is single-quoted: php-fpm runs sendmail_path via the shell and the app-support
        // path contains a space ("Application Support").
        let sendmail = "'\(paths.binary("mailpit").path)' sendmail -S 127.0.0.1:1025"
        // Point a `localhost` MySQL connection at the bundled MySQL's UNIX socket (Laragon-style), so
        // WordPress/Laravel apps using DB_HOST=localhost connect without editing every config — the
        // compiled default socket (/tmp/mysql.sock) doesn't exist in KDWarm's layout. php_value (not
        // admin) so a project can still override it. No quoting: FPM takes the rest of the line as-is.
        let mysqlSocket = paths.serviceSocket("mysql").path
        return """
        [global]
        error_log = \(log)
        daemonize = no
        log_limit = 8192

        [\(poolName)]
        user = \(user)
        listen = \(socket)
        listen.owner = \(user)
        listen.mode = 0660

        pm = dynamic
        pm.max_children = 5
        pm.start_servers = 2
        pm.min_spare_servers = 1
        pm.max_spare_servers = 3
        pm.max_requests = 500

        catch_workers_output = yes
        php_admin_flag[log_errors] = on
        php_admin_value[error_log] = \(log)
        php_admin_value[sendmail_path] = \(sendmail)
        php_value[mysqli.default_socket] = \(mysqlSocket)
        php_value[pdo_mysql.default_socket] = \(mysqlSocket)
        php_value[mysql.default_socket] = \(mysqlSocket)
        """
    }

    /// Write the pool config to `paths.phpFpmPool(poolName)`.
    @discardableResult
    public func write(paths: AppSupportPaths, poolName: String) throws -> URL {
        let url = paths.phpFpmPool(poolName)
        try poolConfig(paths: paths, poolName: poolName)
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
