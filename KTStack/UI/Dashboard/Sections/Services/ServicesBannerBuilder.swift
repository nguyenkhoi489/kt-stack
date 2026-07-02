import KTStackKit
import SwiftUI

struct ServiceBanner: Identifiable {
    let id: String
    let status: ServiceStatus
    let title: String
    let message: String
    var ctaTitle: String?
    var action: (() -> Void)?
}

enum ServicesBannerBuilder {
    @MainActor
    static func banners(
        snapshots: [ServiceSnapshot],
        dns: DNSAutomationService,
        caTrusted: Bool,
        caExists: Bool,
        onEnableDNS: @escaping () -> Void,
        onResetDNS: @escaping () -> Void,
        onOpenTLSSettings: @escaping () -> Void,
        onRestart: @escaping (ServiceKind) -> Void
    ) -> [ServiceBanner] {
        var result: [ServiceBanner] = []

        if case let .conflict(proc) = dns.status {
            result.append(ServiceBanner(
                id: "dns-conflict", status: .error,
                title: "DNS port is in use",
                message: "“\(proc)” is holding port 53, so `.test` resolution is blocked. Reset DNS to take it over.",
                ctaTitle: "Reset DNS", action: onResetDNS
            ))
        } else if let error = dns.lastError, dns.status == .disabled {
            // Enable failed. On signed builds the cause is usually an unapproved helper, which
            // otherwise looks like the button doing nothing, so name the System Settings step.
            result.append(ServiceBanner(
                id: "dns-error", status: .error,
                title: "Couldn't enable `.test` DNS",
                message: dns.usesHelper
                    ? "\(error) Approve KTStack's helper in System Settings > General > Login Items & Extensions, then enable DNS again."
                    : error,
                ctaTitle: "Try again", action: onEnableDNS
            ))
        } else if dns.status == .disabled {
            result.append(ServiceBanner(
                id: "dns-off", status: .warning,
                title: "`.test` DNS is off",
                message: "Sites won't resolve until the DNS resolver is enabled (privileged helper or one-time sudo).",
                ctaTitle: "Enable DNS", action: onEnableDNS
            ))
        }

        if caExists, !caTrusted {
            result.append(ServiceBanner(
                id: "ca-untrusted", status: .warning,
                title: "Local HTTPS CA isn't trusted",
                message: "Secure `.test` sites will warn until KTStack's root CA is trusted in the System Keychain.",
                ctaTitle: "Open TLS Settings", action: onOpenTLSSettings
            ))
        }

        for snap in snapshots where snap.status == .error {
            result.append(ServiceBanner(
                id: "error-\(snap.kind.rawValue)", status: .error,
                title: "\(snap.displayName) stopped responding",
                message: snap.errorMessage ?? "\(snap.displayName) failed to stay running. Restart it or check its logs.",
                ctaTitle: "Restart", action: { onRestart(snap.kind) }
            ))
        }

        let unavailable = snapshots.filter { !$0.isInstalled && !$0.installable }.map(\.displayName)
        if !unavailable.isEmpty {
            result.append(ServiceBanner(
                id: "not-available", status: .info,
                title: "Some services aren't available yet",
                message: "\(unavailable.joined(separator: ", ")) will ship in a later build. Redis and PostgreSQL can be installed now from their row."
            ))
        }
        return result
    }
}
