import Foundation

public struct NginxTLSVhostWriter {
    public static let listenAddress = NginxConfigWriter.listenAddress

    public init() {}

    public func secureVhost(
        domain: String,
        root: URL,
        certFile: URL,
        keyFile: URL,
        phpFpmSocket: URL?,
        nodeProxyPort: Int? = nil,
        accessLog: URL? = nil,
        errorLog: URL? = nil
    ) -> String {
        let routing: String = if let nodeProxyPort {
            NginxConfigWriter.proxyRouting(nodePort: nodeProxyPort)
        } else if let phpFpmSocket {
            phpRouting(socket: phpFpmSocket)
        } else {
            staticRouting()
        }
        let index = phpFpmSocket == nil ? "index.html index.htm" : "index.php index.html"
        return """
        server {
            listen \(Self.listenAddress):443 ssl;
            http2 on;
            server_name \(domain);
            root \(NginxConfigWriter.q(root.path));
            index \(index);\(NginxConfigWriter.logDirectives(access: accessLog, error: errorLog))

            ssl_certificate \(NginxConfigWriter.q(certFile.path));
            ssl_certificate_key \(NginxConfigWriter.q(keyFile.path));
            ssl_protocols TLSv1.2 TLSv1.3;
            ssl_prefer_server_ciphers off;

        \(routing)
        }
        """
    }

    public func redirectVhost(domain: String) -> String {
        """
        server {
            listen \(Self.listenAddress):80;
            server_name \(domain);
            return 301 https://$host$request_uri;
        }
        """
    }

    private func phpRouting(socket: URL) -> String {
        """
            location / {
                try_files $uri $uri/ /index.php?$query_string;
            }

            location ~ \\.php$ {
                fastcgi_pass \(NginxConfigWriter.q("unix:" + socket.path));
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
                fastcgi_param HTTPS            on;
                fastcgi_param REMOTE_ADDR      $remote_addr;
                fastcgi_param REMOTE_PORT      $remote_port;
                fastcgi_param SERVER_ADDR      $server_addr;
                fastcgi_param SERVER_PORT      $server_port;
                fastcgi_param SERVER_NAME      $server_name;
            }

            location ~ /\\.(?!well-known).* {
                deny all;
            }
        """
    }

    private func staticRouting() -> String {
        """
            location / {
                try_files $uri $uri/ =404;
            }

            location ~ /\\.(?!well-known).* {
                deny all;
            }
        """
    }
}
