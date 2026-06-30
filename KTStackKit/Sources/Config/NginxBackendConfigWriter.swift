import Foundation

// Standalone nginx config for one PHP site's loopback backend. The front terminates TLS and
// proxies here over plain HTTP, so SERVER_PORT/SERVER_ADDR/HTTPS are pinned from the
// front-terminated state, not derived from $server_port (which would be the loopback port and
// break framework-generated redirect URLs).
public struct NginxBackendConfigWriter: Sendable {
    public init() {}

    public func config(
        domain: String,
        root: URL,
        phpFpmSocket: URL,
        backendPort: Int,
        secure: Bool,
        pid: URL,
        accessLog: URL,
        errorLog: URL
    ) -> String {
        let q = NginxConfigWriter.q
        let serverPort = secure ? 443 : 80
        let httpsParam = secure ? "\n            fastcgi_param HTTPS            on;" : ""
        return """
        worker_processes 1;
        pid \(q(pid.path));
        error_log \(q(errorLog.path)) warn;

        events {
            worker_connections 1024;
        }

        http {
            access_log \(q(accessLog.path));
            default_type application/octet-stream;
        \(Self.mimeTypes)
            sendfile on;
            keepalive_timeout 65;
            client_max_body_size 256M;

            server {
                listen 127.0.0.1:\(backendPort);
                server_name \(domain);
                root \(q(root.path));
                index index.php index.html;

                location / {
                    try_files $uri $uri/ /index.php?$query_string;
                }

                location ~ \\.php$ {
                    fastcgi_pass \(q("unix:" + phpFpmSocket.path));
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
                    fastcgi_param SERVER_SOFTWARE  nginx;\(httpsParam)
                    fastcgi_param REMOTE_ADDR      $remote_addr;
                    fastcgi_param REMOTE_PORT      $remote_port;
                    fastcgi_param SERVER_ADDR      127.0.0.1;
                    fastcgi_param SERVER_PORT      \(serverPort);
                    fastcgi_param SERVER_NAME      $server_name;
                }

                location ~ /\\.(?!well-known).* {
                    deny all;
                }
            }
        }
        """
    }

    static let mimeTypes = """
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
    """
}
