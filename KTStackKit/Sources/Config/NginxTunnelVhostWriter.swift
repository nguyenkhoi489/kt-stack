import Foundation

public struct NginxTunnelVhostWriter {
    public static let listenAddress = "127.0.0.1"

    public init() {}

    public func vhost(
        site: Site,
        port: Int,
        phpFpmSocket: URL?,
        accessLog: URL? = nil,
        errorLog: URL? = nil,
        publicHost: String? = nil,
        supportsBodyRewrite: Bool = false,
        hostPrependFile: URL? = nil
    ) -> String {
        let root = URL(fileURLWithPath: site.docroot)
        let prepend = publicHost == nil ? nil : hostPrependFile
        let routing = phpFpmSocket.map { phpRouting(socket: $0, localHost: site.domain, publicHost: publicHost, prependFile: prepend) } ?? staticRouting()
        let index = phpFpmSocket == nil ? "index.html index.htm" : "index.php index.html"
        let rewrite = supportsBodyRewrite ? publicHostRewrite(localDomain: site.domain, publicHost: publicHost) : ""
        return """
        server {
            listen \(Self.listenAddress):\(port);
            server_name _;
            root \(NginxConfigWriter.q(root.path));
            index \(index);\(NginxConfigWriter.logDirectives(access: accessLog, error: errorLog))\(rewrite)

        \(routing)
        }
        """
    }

    private func publicHostRewrite(localDomain: String, publicHost: String?) -> String {
        guard let publicHost, !publicHost.isEmpty else { return "" }
        let lines = [
            "sub_filter_once off;",
            "sub_filter_types *;",
            "sub_filter \"https://\(localDomain)\" \"https://\(publicHost)\";",
            "sub_filter \"http://\(localDomain)\" \"https://\(publicHost)\";",
            "sub_filter \"//\(localDomain)\" \"//\(publicHost)\";",
        ]
        return "\n" + lines.map { "    " + $0 }.joined(separator: "\n")
    }

    private func phpRouting(socket: URL, localHost: String, publicHost: String?, prependFile: URL?) -> String {
        let forwardedHost = publicHost ?? localHost
        let prependParam = prependFile.map {
            "\n                fastcgi_param PHP_VALUE                \(NginxConfigWriter.q("auto_prepend_file=" + $0.path));"
        } ?? ""
        return """
            location / {
                try_files $uri $uri/ /index.php?$query_string;
            }

            location ~ \\.php$ {
                fastcgi_pass \(NginxConfigWriter.q("unix:" + socket.path));
                fastcgi_index index.php;
                fastcgi_param SCRIPT_FILENAME          $document_root$fastcgi_script_name;
                fastcgi_param QUERY_STRING             $query_string;
                fastcgi_param REQUEST_METHOD           $request_method;
                fastcgi_param CONTENT_TYPE             $content_type;
                fastcgi_param CONTENT_LENGTH           $content_length;
                fastcgi_param REQUEST_URI              $request_uri;
                fastcgi_param DOCUMENT_URI             $document_uri;
                fastcgi_param DOCUMENT_ROOT            $document_root;
                fastcgi_param SERVER_PROTOCOL          $server_protocol;
                fastcgi_param GATEWAY_INTERFACE        CGI/1.1;
                fastcgi_param SERVER_SOFTWARE          nginx;
                fastcgi_param HTTPS                    on;
                fastcgi_param HTTP_HOST                \(forwardedHost);
                fastcgi_param SERVER_NAME              \(forwardedHost);
                fastcgi_param SERVER_PORT              443;
                fastcgi_param HTTP_X_FORWARDED_HOST    \(forwardedHost);
                fastcgi_param HTTP_X_FORWARDED_PROTO   https;
                fastcgi_param HTTP_X_FORWARDED_PORT    443;
                fastcgi_param REMOTE_ADDR              $remote_addr;
                fastcgi_param REMOTE_PORT              $remote_port;
                fastcgi_param SERVER_ADDR              $server_addr;\(prependParam)
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
