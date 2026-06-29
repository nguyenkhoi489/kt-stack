import Foundation
import Security

public struct CertMinter {
    private let paths: AppSupportPaths
    private let runner: MkcertRunner

    public init(paths: AppSupportPaths, runner: MkcertRunner) {
        self.paths = paths
        self.runner = runner
    }

    public func certExists(name: String) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: paths.siteCert(name).path)
            && fm.fileExists(atPath: paths.siteKey(name).path)
    }

    public enum CertError: LocalizedError {
        case nonLocalDomain(String, tld: String)
        public var errorDescription: String? {
            switch self {
            case let .nonLocalDomain(d, t): "Refusing to mint a certificate for “\(d)” — only .\(t) domains are allowed."
            }
        }
    }

    @discardableResult
    public func mint(name: String, domain: String, tld: String = AppPreferences.defaultTLD) throws -> (cert: URL, key: URL) {
        guard domain.hasSuffix(".\(tld)") else { throw CertError.nonLocalDomain(domain, tld: tld) }
        let cert = paths.siteCert(name), key = paths.siteKey(name)
        try runner.mint(domain: domain, certFile: cert, keyFile: key)
        return (cert, key)
    }

    public func removeCert(name: String) {
        try? FileManager.default.removeItem(at: paths.siteCertDir(name))
    }

    public func pruneOrphans(keeping: Set<String>) {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: paths.certsDir,
            includingPropertiesForKeys: nil
        ) else { return }
        for dir in dirs where !keeping.contains(dir.lastPathComponent) {
            try? fm.removeItem(at: dir)
        }
    }

    public func notAfter(name: String) -> Date? {
        guard let pem = try? Data(contentsOf: paths.siteCert(name)) else { return nil }
        return Self.notAfter(pem: pem)
    }

    public func needsRenewal(name: String, within: TimeInterval = 30 * 24 * 3600) -> Bool {
        guard let exp = notAfter(name: name) else { return true }
        return exp.timeIntervalSinceNow < within
    }

    static func notAfter(pem: Data) -> Date? {
        guard let der = pemToDER(pem),
              let cert = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        let keys = [kSecOIDX509V1ValidityNotAfter] as CFArray
        guard let values = SecCertificateCopyValues(cert, keys, nil) as? [CFString: Any],
              let entry = values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any],
              let seconds = entry[kSecPropertyKeyValue] as? Double else { return nil }

        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    static func pemToDER(_ pem: Data) -> Data? {
        RootCAConstraint.pemToDER(pem)
    }
}

public struct SiteHTTPSProvisioner: Sendable {
    public typealias TrustQuery = @Sendable (URL) -> Bool
    public typealias InstallCA = @Sendable () throws -> Void
    public typealias MintLeaf = @Sendable (String, String) throws -> Void

    private let caCert: URL
    private let tld: String
    private let trustQuery: TrustQuery
    private let installCA: InstallCA
    private let mintLeaf: MintLeaf

    public init(
        caCert: URL,
        tld: String,
        trustQuery: @escaping TrustQuery,
        installCA: @escaping InstallCA,
        mintLeaf: @escaping MintLeaf
    ) {
        self.caCert = caCert
        self.tld = tld
        self.trustQuery = trustQuery
        self.installCA = installCA
        self.mintLeaf = mintLeaf
    }

    public init(
        paths: AppSupportPaths,
        tld: String = AppPreferences.defaultTLD,
        mkcert: MkcertRunner,
        certMinter: CertMinter,
        trustQuery: @escaping TrustQuery = CATrustService.isTrustedInSystemKeychain
    ) {
        self.init(
            caCert: paths.caRootCert,
            tld: tld,
            trustQuery: trustQuery,
            installCA: { try mkcert.install() },
            mintLeaf: { domain, tld in
                try certMinter.mint(name: domain, domain: domain, tld: tld)
            }
        )
    }

    public func enableHTTPS(for site: Site) throws {
        if !trustQuery(caCert) {
            try installCA()
        }
        try mintLeaf(site.domain, tld)
    }
}
