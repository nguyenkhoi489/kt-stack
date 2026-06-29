import Foundation

public final class DnsmasqProxyService: ManagedService, @unchecked Sendable {
    public let kind = ServiceKind.dnsmasq
    public var detail: String {
        "*.test"
    }

    public var logsURL: URL? {
        nil
    }

    public var isInstalled: Bool {
        true
    }

    private let dns: DNSAutomationService

    public init(dns: DNSAutomationService) {
        self.dns = dns
    }

    public func start() async throws {
        await MainActor.run { dns.enable() }
    }

    public func stop() async throws {
        await MainActor.run { dns.disable() }
    }

    public func restart() async throws {
        await MainActor.run { dns.reset() }
    }

    public func probe() async -> ServiceStatus {
        await MainActor.run {
            switch dns.status {
            case .enabled: .running
            case .disabled: .stopped
            case .conflict: .warning
            case .unknown: .stopped
            }
        }
    }
}
