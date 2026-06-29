import Foundation

public struct NginxConfigWriter {
    public static let listenAddress = "0.0.0.0"

    public init() {}

    static func q(_ path: String) -> String {
        "\"\(path)\""
    }

    public func masterConfig(paths: AppSupportPaths, secureCatchAll: Bool = false) -> String {
        """
        worker_processes auto;
        pid \(Self.q(paths.nginxPid.path));
        error_log \(Self.q(paths.nginxErrorLog.path)) warn;

        events {
            worker_connections 1024;
        }

        http {
            access_log \(Self.q(paths.nginxAccessLog.path));
            default_type application/octet-stream;
            types {
                text/html                html htm;
                text/css                 css;
                application/javascript   js;
                application/json         json;
                image/png                png;
                image/jpeg               jpg jpeg;
                image/gif                gif;
                image/svg+xml            svg;
                image/x-icon             ico;
                font/woff2               woff2;
            }
            sendfile on;
            keepalive_timeout 65;

        \(catchAllServers(paths: paths, secure: secureCatchAll))
            include \(Self.q(paths.sitesEnabled.path + "/*.conf"));
        }
        """
    }

    func catchAllServers(paths: AppSupportPaths, secure: Bool) -> String {
        var blocks = """
            server {
                listen \(Self.listenAddress):80 default_server;
                server_name _;
                return 444;
            }
        """
        if secure {
            blocks += "\n\n" + """
                server {
                    listen \(Self.listenAddress):443 ssl default_server;
                    server_name _;
                    ssl_certificate \(Self.q(paths.catchAllCert.path));
                    ssl_certificate_key \(Self.q(paths.catchAllKey.path));
                    return 444;
                }
            """
        }
        return blocks
    }

    public static func logDirectives(access: URL?, error: URL?) -> String {
        var lines: [String] = []
        if let access { lines.append("    access_log \(q(access.path));") }
        if let error { lines.append("    error_log \(q(error.path));") }
        return lines.isEmpty ? "" : "\n" + lines.joined(separator: "\n")
    }

    public func vhost(
        domain: String,
        root: URL,
        phpFpmSocket: URL,
        port: Int = 80,
        accessLog: URL? = nil,
        errorLog: URL? = nil
    ) -> String {
        """
        server {
            listen \(Self.listenAddress):\(port);
            server_name \(domain);
            root \(Self.q(root.path));
            index index.php index.html;\(Self.logDirectives(access: accessLog, error: errorLog))

            location / {
                try_files $uri $uri/ /index.php?$query_string;
            }

            location ~ \\.php$ {
                fastcgi_pass \(Self.q("unix:" + phpFpmSocket.path));
                fastcgi_index index.php;
                fastcgi_param SCRIPT_FILENAME  $document_root$fastcgi_script_name;
                fastcgi_param QUERY_STRING     $query_string;
                fastcgi_param REQUEST_METHOD   $request_method;
                fastcgi_param CONTENT_TYPE     $content_type;
                fastcgi_param CONTENT_LENGTH   $content_length;
                fastcgi_param REQUEST_URI      $request_uri;
                fastcgi_param DOCUMENT_URI     $document_uri;
                fastcgi_param DOCUMENT_ROOT    $document_root;
                fastcgi_param SERVER_PROTOCOL  $server_protocol;
                fastcgi_param GATEWAY_INTERFACE CGI/1.1;
                fastcgi_param SERVER_SOFTWARE  nginx;
                fastcgi_param REMOTE_ADDR      $remote_addr;
                fastcgi_param REMOTE_PORT      $remote_port;
                fastcgi_param SERVER_ADDR      $server_addr;
                fastcgi_param SERVER_PORT      $server_port;
                fastcgi_param SERVER_NAME      $server_name;
            }

            location ~ /\\.(?!well-known).* {
                deny all;
            }
        }
        """
    }

    public func vhostStatic(
        domain: String,
        root: URL,
        port: Int = 80,
        accessLog: URL? = nil,
        errorLog: URL? = nil
    ) -> String {
        """
        server {
            listen \(Self.listenAddress):\(port);
            server_name \(domain);
            root \(Self.q(root.path));
            index index.html index.htm;\(Self.logDirectives(access: accessLog, error: errorLog))

            location / {
                try_files $uri $uri/ =404;
            }

            location ~ /\\.(?!well-known).* {
                deny all;
            }
        }
        """
    }

    public func vhostNodeProxy(
        domain: String,
        nodePort: Int,
        port: Int = 80,
        accessLog: URL? = nil,
        errorLog: URL? = nil
    ) -> String {
        """
        server {
            listen \(Self.listenAddress):\(port);
            server_name \(domain);\(Self.logDirectives(access: accessLog, error: errorLog))

        \(Self.proxyRouting(nodePort: nodePort))
        }
        """
    }

    public static func proxyRouting(nodePort: Int) -> String {
        """
            location / {
                proxy_pass http://127.0.0.1:\(nodePort);
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_read_timeout 86400;
            }
        """
    }

    public enum ConfigError: LocalizedError {
        case invalidDomain(String)
        case invalidPath(String)
        public var errorDescription: String? {
            switch self {
            case let .invalidDomain(d): "Invalid site domain: “\(d)”."
            case let .invalidPath(p): "Invalid site path: “\(p)”."
            }
        }
    }

    public static func isValidDomain(_ domain: String) -> Bool {
        let label = "[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?"
        return domain.range(of: "^\(label)(\\.\(label))+$", options: .regularExpression) != nil
    }

    public static func isSafePath(_ path: String) -> Bool {
        !path.isEmpty && path.rangeOfCharacter(from: CharacterSet(charactersIn: ";{}\n\r")) == nil
    }

    @discardableResult
    public func writeDemo(
        paths: AppSupportPaths,
        domain: String,
        siteRoot: URL,
        poolName: String,
        port: Int = 80
    ) throws -> (conf: URL, vhost: URL) {
        guard Self.isValidDomain(domain) else { throw ConfigError.invalidDomain(domain) }
        guard Self.isSafePath(siteRoot.path) else { throw ConfigError.invalidPath(siteRoot.path) }
        try masterConfig(paths: paths)
            .write(to: paths.nginxConf, atomically: true, encoding: .utf8)
        let vhostURL = paths.vhost(poolName)
        try vhost(domain: domain, root: siteRoot, phpFpmSocket: paths.phpFpmSocket(poolName), port: port)
            .write(to: vhostURL, atomically: true, encoding: .utf8)
        return (paths.nginxConf, vhostURL)
    }
}
