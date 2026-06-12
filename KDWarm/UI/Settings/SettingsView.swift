import SwiftUI
import AppKit
import KDWarmKit

/// Settings scene (design-guidelines §10): a segmented sub-nav over `Form`s. The General tab edits the
/// persisted preferences (sites root + dev TLD); changing the TLD reconciles root DNS then prompts a
/// relaunch. A segmented Picker (not a `TabView`) is used so the header lines up with the other
/// dashboard sections — a `TabView` hoists its tabs into the window toolbar and hides the title.
struct SettingsView: View {
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General", services = "Services", tls = "TLS", advanced = "Advanced"
        var id: String { rawValue }
    }
    @State private var tab: SettingsTab = .general

    // Injected via init, NOT @EnvironmentObject: SwiftUI's `Settings` scene evaluates its body during
    // app/menu setup before scene-level .environmentObject modifiers are in scope, which traps an
    // @EnvironmentObject lookup. Init-injection (like TLSSettingsView) is reliable here.
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var dns: DNSAutomationService
    /// Read-only here — used to list the sites a TLD change would orphan. Not observed (the warning
    /// is computed when the confirm dialog opens, not live).
    let server: LocalServerController
    @ObservedObject var caTrust: CATrustService
    @ObservedObject var updater: UpdaterController
    @ObservedObject var uninstaller: UninstallService
    @State private var confirmUninstall = false

    /// Mirrors `preferences.tld` so the Picker shows the current value; an actual change routes
    /// through the confirm dialog before it is applied (and is reverted on cancel/failure).
    @State private var selectedTLD: String
    @State private var pendingTLD: String?
    @State private var confirmTLDChange = false
    @State private var tldError: String?
    @State private var awaitingRelaunch = false

    init(preferences: AppPreferences,
         dns: DNSAutomationService,
         server: LocalServerController,
         caTrust: CATrustService,
         updater: UpdaterController,
         uninstaller: UninstallService) {
        self.preferences = preferences
        self.dns = dns
        self.server = server
        self.caTrust = caTrust
        self.updater = updater
        self.uninstaller = uninstaller
        _selectedTLD = State(initialValue: preferences.tld)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Same toolbar-row + Divider shape as the Sites/Services sections so the header aligns.
            // Full-width segmented control → the 4 tabs split the row evenly and stay centered.
            Picker("", selection: $tab) {
                ForEach(SettingsTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(KDSpacing.space2)
            Divider()
            tabContent
        }
        // No fixed frame here: the standalone Settings scene sizes it (see KDWarmApp); inside the
        // Dashboard it fills the detail pane so its header lines up with the other sections.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .general:  generalTab
        case .services: servicesTab
        case .tls:      TLSSettingsView(caTrust: caTrust)
        case .advanced: advancedTab
        }
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
                Text("Removes all KDWarm services, the .\(preferences.tld) DNS resolver, the local CA trust, and all app data, runtimes and databases.")
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
            Section("Sites") {
                HStack {
                    Text("Sites root")
                    Spacer()
                    Text(preferences.sitesRootPath)
                        .font(KDFont.footnote).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { chooseSitesRoot() }
                }
            }
            Section("Local domain") {
                Picker("Dev TLD", selection: $selectedTLD) {
                    ForEach(AppPreferences.safeTLDs, id: \.self) { Text(".\($0)").tag($0) }
                }
                .disabled(dns.isBusy || awaitingRelaunch)
                .onChange(of: selectedTLD) { newValue in
                    guard newValue != preferences.tld else { return }
                    pendingTLD = newValue
                    confirmTLDChange = true
                }
                Text("Changing the TLD rewrites the system DNS resolver and dnsmasq, then relaunches KDWarm. Existing sites keep their current domain until you re-edit them.")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
                if dns.isBusy {
                    Label("Updating DNS resolver…", systemImage: "arrow.triangle.2.circlepath")
                        .font(KDFont.footnote)
                }
                if let tldError {
                    Label(tldError, systemImage: "exclamationmark.triangle.fill")
                        .font(KDFont.footnote).foregroundStyle(.red)
                }
            }
            Toggle("Launch KDWarm at login", isOn: .constant(false)).disabled(true)
        }
        .formStyle(.grouped)
        .padding(KDSpacing.space4)
        .confirmationDialog("Change the dev TLD to .\(pendingTLD ?? "")?",
                            isPresented: $confirmTLDChange) {
            Button("Change & Relaunch", role: .destructive) { applyTLDChange() }
            Button("Cancel", role: .cancel) { selectedTLD = preferences.tld }
        } message: {
            Text(tldChangeMessage)
        }
    }

    /// Sites whose domain would stop resolving after the TLD change (they keep their old domain).
    private var affectedSites: [Site] {
        server.registry.sites.filter { $0.domain.hasSuffix(".\(preferences.tld)") }
    }

    private var tldChangeMessage: String {
        let count = affectedSites.count
        let base = "KDWarm will reconfigure local DNS (one admin step) and relaunch to apply the new TLD."
        guard count > 0 else { return base }
        let names = affectedSites.prefix(5).map(\.domain).joined(separator: ", ")
        let more = count > 5 ? " (+\(count - 5) more)" : ""
        return base + "\n\n\(count) existing site\(count == 1 ? "" : "s") keep their .\(preferences.tld) domain and will stop resolving until re-edited: \(names)\(more)."
    }

    private func chooseSitesRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = preferences.sitesRootURL
        if panel.runModal() == .OK, let url = panel.url {
            preferences.setSitesRootPath(url.path)
        }
    }

    private func applyTLDChange() {
        guard let target = pendingTLD else { selectedTLD = preferences.tld; return }
        tldError = nil
        dns.changeTLD(to: target) { result in
            switch result {
            case .success:
                _ = preferences.setTLD(target)   // persist so the next launch bakes the new TLD
                awaitingRelaunch = true
                relaunchApp()
            case .failure(let error):
                tldError = error.localizedDescription
                selectedTLD = preferences.tld     // revert the picker; nothing was persisted
            }
        }
    }

    /// Relaunch the app so the registry/DNS/cert layers re-read the new TLD at init (the apply model
    /// is relaunch-required — values bake once at launch; no live re-injection). On a launch failure
    /// we do NOT terminate (that would leave the user with no app); DNS + the pref are already
    /// committed, so we surface a "quit and reopen" message and the next manual launch applies it.
    private func relaunchApp() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error {
                    awaitingRelaunch = false
                    tldError = "TLD changed — quit and reopen KDWarm to apply it. (Auto-relaunch failed: \(error.localizedDescription))"
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private var servicesTab: some View {
        Form {
            LabeledContent("Reverse proxy", value: "Nginx")
            LabeledContent("Local DNS", value: "dnsmasq · /etc/resolver/\(preferences.tld)")
            LabeledContent("Local TLS", value: "mkcert (vendored)")
        }
        .formStyle(.grouped)
        .padding(KDSpacing.space4)
    }
}
