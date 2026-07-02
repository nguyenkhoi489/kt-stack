import Foundation

public struct PHPFPMPoolWriter {
    public init() {}

    public func poolConfig(
        paths: AppSupportPaths,
        poolName: String,
        user: String = NSUserName()
    ) -> String {
        let socket = paths.phpFpmSocket(poolName).path
        let log = paths.phpFpmLog(poolName).path

        let sendmail = "'\(paths.binary("mailpit").path)' sendmail -S 127.0.0.1:1025"

        let mysqlSocket = paths.serviceSocket("mysql").path
        // error_log and sendmail_path use php_admin_value so a user-edited php.ini cannot redirect
        // logs or outbound mail; the mysqli socket lines stay php_value so users can override them.
        let base = """
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
        """
        let magickLines = ImageMagickEnvironment
            .sortedVariables(modulesDir: paths.phpModulesDir(version: poolName))
            .map { "env[\($0.key)] = \($0.value)" }
        guard !magickLines.isEmpty else { return base }
        return base + "\n" + magickLines.joined(separator: "\n")
    }

    @discardableResult
    public func write(paths: AppSupportPaths, poolName: String) throws -> URL {
        let url = paths.phpFpmPool(poolName)
        try poolConfig(paths: paths, poolName: poolName)
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
