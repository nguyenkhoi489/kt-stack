import Foundation

// Front-terminator routing vhost for a PHP site. The front owns :80/:443 and TLS; it proxies
// the request to the site's loopback backend (nginx or, later, apache) on backendPort. Static
// and node sites are served by the front directly and do not use this writer.
public struct NginxFrontProxyWriter {
    public init() {}

    public func vhost(
        domain: String,
        backendPort: Int,
        secure: Bool,
        certFile: URL?,
        keyFile: URL?,
        engine: String = "nginx",
        accessLog: URL? = nil,
        errorLog: URL? = nil
    ) -> String {
        let q = NginxConfigWriter.q
        let logs = NginxConfigWriter.logDirectives(access: accessLog, error: errorLog)
        // Surface which backend actually serves this site; the front's own Server header is always
        // nginx, so this is the honest signal for `curl -I`.
        let engineHeader = "\n    add_header X-KTStack-Engine \(engine) always;"
        guard secure, let certFile, let keyFile else {
            return """
            server {
                listen \(NginxConfigWriter.listenAddress):80;
                server_name \(domain);\(logs)\(engineHeader)

            \(routing(backendPort: backendPort, scheme: "http"))
            }
            """
        }
        return """
        server {
            listen \(NginxConfigWriter.listenAddress):80;
            server_name \(domain);
            return 301 https://$host$request_uri;
        }

        server {
            listen \(NginxConfigWriter.listenAddress):443 ssl;
            http2 on;
            server_name \(domain);\(logs)\(engineHeader)

            ssl_certificate \(q(certFile.path));
            ssl_certificate_key \(q(keyFile.path));
            ssl_protocols TLSv1.2 TLSv1.3;
            ssl_prefer_server_ciphers off;

        \(routing(backendPort: backendPort, scheme: "https"))
        }
        """
    }

    private func routing(backendPort: Int, scheme: String) -> String {
        """
            location / {
                proxy_pass http://127.0.0.1:\(backendPort);
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto \(scheme);
                proxy_read_timeout 86400;
                client_max_body_size 256M;
            }
        """
    }
}
