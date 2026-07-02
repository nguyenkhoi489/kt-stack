import AppKit
import KTStackKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var dns: DNSAutomationService
    let server: LocalServerController
    @ObservedObject var runtimes: RuntimeManager
    @ObservedObject var caTrust: CATrustService
    @ObservedObject var updater: UpdaterController
    @ObservedObject var uninstaller: UninstallService

    @State private var confirmUninstall = false
    @State private var selectedTLD: String
    @State private var tldDraft: String
    @State private var pendingTLD: String?
    @State private var confirmTLDChange = false
    @State private var tldError: String?
    @State private var awaitingRelaunch = false
    @State private var showTLS = false
    @State private var showShell = false

    init(
        preferences: AppPreferences,
        dns: DNSAutomationService,
        server: LocalServerController,
        runtimes: RuntimeManager,
        caTrust: CATrustService,
        updater: UpdaterController,
        uninstaller: UninstallService
    ) {
        self.preferences = preferences
        self.dns = dns
        self.server = server
        self.runtimes = runtimes
        self.caTrust = caTrust
        self.updater = updater
        self.uninstaller = uninstaller
        _selectedTLD = State(initialValue: preferences.tld)
        _tldDraft = State(initialValue: preferences.tld)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings").font(KTType.screenTitle).tracking(KTType.screenTitleTracking).foregroundStyle(KTColor.ink)
                .padding(.horizontal, KTSpacing.screenGutter).padding(.top, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    generalGroup
                    sitesGroup
                    updatesGroup
                    maintenanceGroup
                    developerGroup
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, KTSpacing.screenGutter).padding(.top, 18).padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KTColor.contentBg)
        .sheet(isPresented: $showTLS) { sheetWrapper("HTTPS Certificates", { showTLS = false }) { TLSSettingsView(caTrust: caTrust) } }
        .sheet(isPresented: $showShell) { sheetWrapper("Shell Integration", { showShell = false }) { ShellIntegrationSheetBody() } }
        .confirmationDialog("Change the dev TLD to .\(pendingTLD ?? "")?", isPresented: $confirmTLDChange) {
            Button("Change & Relaunch", role: .destructive) { applyTLDChange() }
            Button("Cancel", role: .cancel) { selectedTLD = preferences.tld; tldDraft = preferences.tld }
        } message: { Text(tldChangeMessage) }
        .confirmationDialog("Uninstall KTStack and remove all data?", isPresented: $confirmUninstall) {
            Button("Uninstall / Reset", role: .destructive) { uninstaller.uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stops all services and permanently deletes app data, runtimes and databases. This cannot be undone.")
        }
    }

    private var generalGroup: some View {
        KTSettingsGroup(title: "General") {
            KTSettingsRow(title: "Launch at login", subtitle: "Start KTStack when you log in to macOS.") {
                KTToggle(isOn: preferences.launchAtLogin, action: toggleLaunchAtLogin)
            }
            KTSettingsRow(title: "Auto-start server", subtitle: "Bring the server up automatically on launch.") {
                KTToggle(isOn: preferences.autoStartServer) { preferences.autoStartServer.toggle() }
            }
            KTSettingsRow(title: "Show in menu bar", subtitle: "Quick-access icon. If hidden, reopen KTStack from Finder.", showDivider: false) {
                KTToggle(isOn: preferences.showInMenuBar) { preferences.showInMenuBar.toggle() }
            }
        }
    }

    private var sitesGroup: some View {
        KTSettingsGroup(title: "Sites & Network") {
            KTSettingsRow(title: "Sites root", subtitle: preferences.sitesRootPath) {
                KTSettingsTextButton(title: "Choose…", action: chooseSitesRoot)
            }
            KTSettingsRow(title: "Default PHP version", subtitle: "Applied to newly created sites.") {
                defaultPHPMenu
            }
            KTSettingsRow(title: "Local TLD", subtitle: tldError ?? "Domain suffix for resolved sites. Press return to apply.") {
                localTLDField
            }
            KTSettingsRow(title: "Serve over HTTPS", subtitle: "Issue trusted local certificates per site.", showDivider: false) {
                KTToggle(isOn: preferences.serveHTTPSByDefault) { preferences.serveHTTPSByDefault.toggle() }
            }
        }
    }

    private var defaultPHPMenu: some View {
        let installed = runtimes.installed[.php] ?? []
        let current = runtimes.defaultVersion(.php)
        return KTDropdown(
            width: 150,
            options: installed.map { version in
                KTDropdownOption(label: "PHP \(version)", active: version == current) {
                    runtimes.setGlobalDefault(.php, version)
                }
            }
        ) {
            KTDropdownChevronLabel(text: current.map { "PHP \($0)" } ?? "—")
        }
        .fixedSize()
        .disabled(installed.isEmpty)
    }

    private var localTLDField: some View {
        HStack(spacing: 1) {
            Text(".").font(.jbMono(13, .regular)).foregroundStyle(KTColor.ink2)
            TextField("test", text: $tldDraft)
                .textFieldStyle(.plain)
                .font(.jbMono(13, .regular))
                .foregroundStyle(KTColor.ink2)
                .frame(width: 88)
                .onSubmit(commitTLD)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KTColor.fieldBg))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(KTColor.fieldBorder, lineWidth: 0.5))
        .disabled(dns.isBusy || awaitingRelaunch)
    }

    private func commitTLD() {
        let next = tldDraft.trimmingCharacters(in: .whitespaces).lowercased()
        tldDraft = next
        guard next != preferences.tld else { tldError = nil; return }
        guard AppPreferences.isValidTLD(next) else {
            tldError = "“\(next)” isn’t a valid TLD."
            tldDraft = preferences.tld
            return
        }
        tldError = nil
        selectedTLD = next
        pendingTLD = next
        confirmTLDChange = true
    }

    private var updatesGroup: some View {
        KTSettingsGroup(title: "Updates") {
            KTSettingsRow(title: "Automatic updates", subtitle: "Download and install updates in the background.") {
                KTToggle(isOn: preferences.automaticUpdates, action: toggleAutomaticUpdates)
            }
            KTSettingsRow(title: "Release channel", subtitle: "Currently on \(versionString).") {
                releaseChannelMenu
            }
            KTSettingsRow(title: "Check for updates", subtitle: "Look for a newer version now.", showDivider: false) {
                KTSettingsTextButton(title: "Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }

    private var releaseChannelMenu: some View {
        KTDropdown(
            width: 140,
            options: AppPreferences.ReleaseChannel.allCases.map { channel in
                KTDropdownOption(label: channel.label, active: channel == preferences.releaseChannel) {
                    selectChannel(channel)
                }
            }
        ) {
            KTDropdownChevronLabel(text: preferences.releaseChannel.label)
        }
        .fixedSize()
    }

    private var maintenanceGroup: some View {
        KTSettingsGroup(title: "Maintenance") {
            KTSettingsRow(title: "Local HTTPS certificates", subtitle: "Manage the local certificate authority and trust.") {
                KTSettingsTextButton(title: "Manage…") { showTLS = true }
            }
            KTSettingsRow(title: "Terminal shell integration", subtitle: "Use per-project PHP/Node versions from the terminal.") {
                KTSettingsTextButton(title: "Manage…") { showShell = true }
            }
            KTSettingsRow(
                title: "Reset & Uninstall",
                subtitle: "Remove all services, DNS resolver, CA trust, app data, runtimes and databases.",
                showDivider: false
            ) {
                KTSettingsTextButton(title: "Uninstall…", danger: true) { confirmUninstall = true }
                    .disabled(uninstaller.state == .running)
            }
        }
    }

    private var developerGroup: some View {
        KTSettingsGroup(title: "Developer") {
            KTSettingsRow(
                title: "Developer diagnostics",
                subtitle: "Log verbose service startup details to diagnostics.log. Turn on when a service won’t start, then reproduce."
            ) {
                KTToggle(isOn: preferences.devMode) { preferences.devMode.toggle() }
            }
            KTSettingsRow(
                title: "Diagnostics log",
                subtitle: "Reveal logs/diagnostics.log in Finder.",
                showDivider: false
            ) {
                KTSettingsTextButton(title: "Reveal…", action: revealDiagnosticsLog)
            }
        }
    }

    private func revealDiagnosticsLog() {
        let url = AppSupportPaths().serviceLog("diagnostics")
        let target = FileManager.default.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(short)"
    }

    private func toggleLaunchAtLogin() {
        let target = !preferences.launchAtLogin
        if LoginItemService.setEnabled(target) { preferences.launchAtLogin = target }
        else { preferences.launchAtLogin = LoginItemService.isEnabled }
    }

    private func toggleAutomaticUpdates() {
        let target = !preferences.automaticUpdates
        preferences.automaticUpdates = target
        updater.setAutomaticChecks(target)
    }

    private func selectChannel(_ channel: AppPreferences.ReleaseChannel) {
        preferences.releaseChannel = channel
        updater.setChannel(channel == .beta ? "beta" : "")
    }

    private var affectedSites: [Site] {
        server.registry.sites.filter { $0.domain.hasSuffix(".\(preferences.tld)") }
    }

    private var tldChangeMessage: String {
        let count = affectedSites.count
        let base = "KTStack will reconfigure local DNS (one admin step) and relaunch to apply the new TLD."
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
                _ = preferences.setTLD(target)
                awaitingRelaunch = true
                relaunchApp()
            case let .failure(error):
                tldError = error.localizedDescription
                selectedTLD = preferences.tld
            }
        }
    }

    private func relaunchApp() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error {
                    awaitingRelaunch = false
                    tldError = "TLD changed — quit and reopen KTStack to apply it. (Auto-relaunch failed: \(error.localizedDescription))"
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func sheetWrapper(
        _ title: String,
        _ onDone: @escaping () -> Void,
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.jbMono(15, .regular)).foregroundStyle(KTColor.ink)
                Spacer()
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            Divider()
            content()
        }
        .frame(width: 540, height: 480)
    }
}

private struct ShellIntegrationSheetBody: View {
    var body: some View {
        Form { ShellIntegrationView() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(KTColor.contentBg)
    }
}
