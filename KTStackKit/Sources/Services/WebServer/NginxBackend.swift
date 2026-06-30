import Foundation

public struct NginxBackend: WebServerBackend {
    public let engine: WebServerEngine = .nginx

    private let writer = NginxConfigWriter()
    private let tls = NginxTLSVhostWriter()

    public init() {}

    public func siteConfig(context: BackendRenderContext) -> String {
        let site = context.site

        if site.secure, let certFile = context.certFile, let keyFile = context.keyFile {
            return tls.redirectVhost(domain: site.domain) + "\n\n"
                + tls.secureVhost(
                    domain: site.domain,
                    root: context.root,
                    certFile: certFile,
                    keyFile: keyFile,
                    phpFpmSocket: context.phpFpmSocket,
                    nodeProxyPort: context.nodeProxyPort,
                    accessLog: context.accessLog,
                    errorLog: context.errorLog
                )
        }

        switch site.type {
        case .php:
            return writer.vhost(
                domain: site.domain,
                root: context.root,
                phpFpmSocket: context.phpFpmSocket!,
                port: context.port,
                accessLog: context.accessLog,
                errorLog: context.errorLog
            )
        case .node where context.nodeProxyPort != nil:
            return writer.vhostNodeProxy(
                domain: site.domain,
                nodePort: context.nodeProxyPort!,
                port: context.port,
                accessLog: context.accessLog,
                errorLog: context.errorLog
            )
        case .staticSite, .node:
            return writer.vhostStatic(
                domain: site.domain,
                root: context.root,
                port: context.port,
                accessLog: context.accessLog,
                errorLog: context.errorLog
            )
        }
    }
}
