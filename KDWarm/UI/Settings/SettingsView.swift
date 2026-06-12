import SwiftUI
import KDWarmKit

/// Settings scene placeholder (design-guidelines §10): `TabView` of `Form`s. Real
/// preference bindings land alongside the subsystems they configure in later phases.
struct SettingsView: View {
    // Injected via init, NOT @EnvironmentObject: SwiftUI's `Settings` scene evaluates its body during
    // app/menu setup before scene-level .environmentObject modifiers are in scope, which traps an
    // @EnvironmentObject lookup. Init-injection (like TLSSettingsView) is reliable here.
    @ObservedObject var caTrust: CATrustService
    @ObservedObject var updater: UpdaterController
    @ObservedObject var uninstaller: UninstallService
    @State private var confirmUninstall = false

    init(caTrust: CATrustService, updater: UpdaterController, uninstaller: UninstallService) {
        self.caTrust = caTrust
        self.updater = updater
        self.uninstaller = uninstaller
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            servicesTab
                .tabItem { Label("Services", systemImage: "server.rack") }
            TLSSettingsView(caTrust: caTrust)
                .tabItem { Label("TLS", systemImage: "lock.shield") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 480, height: 360)
    }

    /// Distinct status glyph: done = check, failed = warning, in-progress = dotted.
    private var uninstallGlyph: String {
        switch uninstaller.state {
        case .done:        return "checkmark.circle"
        case .failed:      return "exclamationmark.triangle.fill"
        default:           return "circle.dotted"
        }
    }

    private var advancedTab: some View {
        Form {
            Section("Software Update") {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            Section("Uninstall") {
                Text("Removes all KDWarm services, the .test DNS resolver, the local CA trust, and all app data, runtimes and databases.")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
                Button("Uninstall / Reset KDWarm…", role: .destructive) { confirmUninstall = true }
                    .disabled(uninstaller.state == .running)
                if !uninstaller.log.isEmpty {
                    ForEach(uninstaller.log, id: \.self) { line in
                        Label(line, systemImage: uninstallGlyph).font(KDFont.footnote)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(KDSpacing.space4)
        .confirmationDialog("Uninstall KDWarm and remove all data?", isPresented: $confirmUninstall) {
            Button("Uninstall / Reset", role: .destructive) { uninstaller.uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stops all services and permanently deletes app data, runtimes and databases. This cannot be undone.")
        }
    }

    private var generalTab: some View {
        Form {
            LabeledContent("Sites root", value: "~/Sites/WWW")
            LabeledContent("Default TLD", value: ".test")
            Toggle("Launch KDWarm at login", isOn: .constant(false)).disabled(true)
        }
        .formStyle(.grouped)
        .padding(KDSpacing.space4)
    }

    private var servicesTab: some View {
        Form {
            LabeledContent("Reverse proxy", value: "Nginx")
            LabeledContent("Local DNS", value: "dnsmasq · /etc/resolver/test")
            LabeledContent("Local TLS", value: "mkcert (vendored)")
        }
        .formStyle(.grouped)
        .padding(KDSpacing.space4)
    }
}
