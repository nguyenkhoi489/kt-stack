import Foundation

let helperBundleVersion = "0.2.0"

final class HelperService: NSObject, HelperXPCProtocol {
    private let dns = HelperDNSManager()
    private let ca = HelperCAManager()

    func ping(reply: @escaping (String) -> Void) {
        reply(helperBundleVersion)
    }

    func helperVersion(reply: @escaping (String) -> Void) {
        reply(helperBundleVersion)
    }

    func enableDNS(tld: String, reply: @escaping (Bool, String?) -> Void) {
        let r = dns.enableDNS(tld: tld); reply(r.0, r.1)
    }

    func disableDNS(tld: String, reply: @escaping (Bool, String?) -> Void) {
        let r = dns.disableDNS(tld: tld); reply(r.0, r.1)
    }

    func resetDNS(tld: String, reply: @escaping (Bool, String?) -> Void) {
        let r = dns.resetDNS(tld: tld); reply(r.0, r.1)
    }

    func setTLD(old: String, new: String, reply: @escaping (Bool, String?) -> Void) {
        let r = dns.setTLD(old: old, new: new); reply(r.0, r.1)
    }

    func dnsStatus(tld: String, reply: @escaping (Bool, Bool, String?) -> Void) {
        let s = dns.status(tld: tld); reply(s.resolverPresent, s.dnsmasqRunning, s.conflict)
    }

    func installRootCA(pemData: Data, reply: @escaping (Bool, String?) -> Void) {
        let r = ca.installRootCA(pemData: pemData); reply(r.0, r.1)
    }

    func removeRootCA(certSHA1: String, reply: @escaping (Bool, String?) -> Void) {
        let r = ca.removeRootCA(certSHA1: certSHA1); reply(r.0, r.1)
    }
}

final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard HelperSignatureValidator.isTrustedClient(connection) else { return false }
        connection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        return true
    }
}

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperIdentity.machServiceName)
listener.delegate = delegate
listener.resume()
dispatchMain()
