import Foundation

@objc
public protocol HelperXPCProtocol {
    func ping(reply: @escaping (String) -> Void)

    func enableDNS(tld: String, reply: @escaping (Bool, String?) -> Void)

    func disableDNS(tld: String, reply: @escaping (Bool, String?) -> Void)

    func resetDNS(tld: String, reply: @escaping (Bool, String?) -> Void)

    func setTLD(old: String, new: String, reply: @escaping (Bool, String?) -> Void)

    func dnsStatus(tld: String, reply: @escaping (Bool, Bool, String?) -> Void)

    func helperVersion(reply: @escaping (String) -> Void)

    func installRootCA(pemData: Data, reply: @escaping (Bool, String?) -> Void)

    func removeRootCA(certSHA1: String, reply: @escaping (Bool, String?) -> Void)
}

public struct HelperDNSStatus: Sendable, Equatable {
    public let resolverPresent: Bool
    public let dnsmasqRunning: Bool

    public let conflictProcess: String?

    public init(resolverPresent: Bool, dnsmasqRunning: Bool, conflictProcess: String?) {
        self.resolverPresent = resolverPresent
        self.dnsmasqRunning = dnsmasqRunning
        self.conflictProcess = conflictProcess
    }

    public var isHealthy: Bool {
        resolverPresent && dnsmasqRunning && conflictProcess == nil
    }

    public static let unknown = HelperDNSStatus(resolverPresent: false, dnsmasqRunning: false, conflictProcess: nil)
}
