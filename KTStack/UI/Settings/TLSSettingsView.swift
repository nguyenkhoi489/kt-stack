import KTStackKit
import SwiftUI

struct TLSSettingsView: View {
    @ObservedObject var caTrust: CATrustService

    var body: some View {
        Form {
            Section {
                LabeledContent("Certificate authority") {
                    HStack(spacing: KDSpacing.space2) {
                        Image(systemName: statusIcon).foregroundStyle(statusTint)
                        Text(statusText)
                    }
                }
                LabeledContent("Firefox / NSS") {
                    Text("Installed if Firefox is present (via mkcert)").foregroundStyle(.secondary)
                }
            } header: {
                Text("Local TLS (mkcert)")
            } footer: {
                Text("Installing a local root CA lets your browser trust *.test certificates. It only affects this Mac and can be removed any time. Note: once a site has been served over HTTPS, browsers may remember it (HSTS) and refuse plain http until that expires.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    if caTrust.isBusy { ProgressView().controlSize(.small) }
                    Spacer()
                    if caTrust.isTrusted {
                        Button("Untrust CA", role: .destructive) { caTrust.untrust() }.disabled(caTrust.isBusy)
                    } else {
                        Button("Trust CA") { caTrust.install() }.disabled(caTrust.isBusy)
                    }
                }
                if let error = caTrust.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(KDFont.footnote).foregroundStyle(Color.KDStatus.error)
                }
            }
        }
        .formStyle(.grouped)
        .padding(KDSpacing.space4)
        .onAppear { caTrust.refresh() }
    }

    private var statusText: String {
        switch caTrust.status {
        case .trusted: "Trusted in System Keychain"
        case .untrusted: "Generated, not trusted"
        case .notInstalled: "Not installed"
        }
    }

    private var statusIcon: String {
        switch caTrust.status {
        case .trusted: "checkmark.seal.fill"
        case .untrusted: "exclamationmark.seal"
        case .notInstalled: "seal"
        }
    }

    private var statusTint: Color {
        switch caTrust.status {
        case .trusted: Color.KDStatus.running
        case .untrusted: Color.KDStatus.warning
        case .notInstalled: .secondary
        }
    }
}
