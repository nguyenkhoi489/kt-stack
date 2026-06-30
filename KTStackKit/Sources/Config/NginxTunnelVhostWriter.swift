import Foundation

// Tunnel origin vhost (cloudflared connects here). For PHP it proxies to the site's loopback
// backend so the site's actual engine (nginx or apache) serves it, not a FastCGI shortcut that
// would bypass Apache. The public host is passed via the Host header (so PHP sees it as
// HTTP_HOST), and sub_filter rewrites the local domain to the public host in the response body.
// Static/node sites have no backend, so the tunnel serves their docroot directly.
public struct NginxTunnelVhostWriter {
    public static let listenAddress = "127.0.0.1"

    public init() {}

    public func vhost(
        site: Site,
        port: Int,
        backendPort: Int?,
        accessLog: URL? = nil,
        errorLog: URL? = nil,
        publicHost: String? = nil,
        supportsBodyRewrite: Bool = false
    ) -> String {
        let logs = NginxConfigWriter.logDirectives(access: accessLog, error: errorLog)
        if let backendPort {
            let rewrite = supportsBodyRewrite ? publicHostRewrite(localDomain: site.domain, publicHost: publicHost) : ""
            return """
            server {
                listen \(Self.listenAddress):\(port);
                server_name _;\(logs)

            \(proxyRouting(backendPort: backendPort, forwardedHost: publicHost ?? site.domain, rewrite: rewrite))
            }
            """
        }
        let root = URL(fileURLWithPath: site.docroot)
        return """
        server {
            listen \(Self.listenAddress):\(port);
            server_name _;
            root \(NginxConfigWriter.q(root.path));
            index index.html index.htm;\(logs)

        \(staticRouting())
        }
        """
    }

    private func proxyRouting(backendPort: Int, forwardedHost: String, rewrite: String) -> String {
        // Drop Accept-Encoding so the backend returns an uncompressed body sub_filter can rewrite.
        let acceptEncoding = rewrite.isEmpty ? "" : "\n            proxy_set_header Accept-Encoding \"\";"
        return """
            location / {
                proxy_pass http://127.0.0.1:\(backendPort);
                proxy_http_version 1.1;
                proxy_set_header Host \(forwardedHost);
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto https;
                proxy_set_header X-Forwarded-Host \(forwardedHost);
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
                proxy_read_timeout 86400;\(acceptEncoding)\(rewrite)
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
        return "\n" + lines.map { "        " + $0 }.joined(separator: "\n")
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
