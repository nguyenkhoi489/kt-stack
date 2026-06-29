import KTStackKit
import SwiftUI

struct DNSStatusBar: View {
    @ObservedObject var dns: DNSAutomationService

    var body: some View {
        HStack(spacing: KDSpacing.space2) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(KDFont.footnote)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if dns.isBusy {
                ProgressView().controlSize(.small)
            } else {
                switch dns.status {
                case .enabled:
                    Button("Reset") { dns.reset() }
                    Button("Disable DNS") { dns.disable() }
                case .conflict:
                    Button("Reset") { dns.reset() }
                default:
                    Button("Enable DNS") { dns.enable() }
                }
            }
        }
        .padding(KDSpacing.space2)
        .background(Color.secondary.opacity(0.06))
    }

    private var title: String {
        switch dns.status {
        case .enabled: "Automatic DNS is on — *.test resolves"
        case .disabled: "Automatic DNS is off"
        case let .conflict(p): "DNS port conflict: \(p)"
        case .unknown: "DNS status unknown"
        }
    }

    private var subtitle: String {
        dns.usesHelper
            ? "Managed by the KTStack privileged helper."
            : "Uses a one-time admin password (helper signing arrives later)."
    }

    private var icon: String {
        switch dns.status {
        case .enabled: "checkmark.seal.fill"
        case .conflict: "exclamationmark.triangle.fill"
        default: "network"
        }
    }

    private var tint: Color {
        switch dns.status {
        case .enabled: Color.KDStatus.running
        case .conflict: Color.KDStatus.warning
        default: .secondary
        }
    }
}

struct HelperApprovalView: View {
    @ObservedObject var dns: DNSAutomationService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Label("Enable automatic .test DNS", systemImage: "network")
                .font(KDFont.title)
            Text(
                dns.usesHelper
                    ? "KTStack installs a small background helper to run a local DNS resolver for *.test. macOS will ask you to allow it in System Settings → Login Items."
                    : "KTStack will ask for your admin password once to set up local DNS for *.test. No background item is installed on this build."
            )
            .font(KDFont.body).foregroundStyle(.secondary)
            if let error = dns.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(KDFont.footnote).foregroundStyle(Color.KDStatus.error)
            }
            HStack {
                Spacer()
                Button("Not now") { dismiss() }
                Button("Enable DNS") { dns.enable(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(dns.isBusy)
            }
        }
        .padding(KDSpacing.space4)
        .frame(width: 460)
    }
}
