import SwiftUI
import KTStackKit


struct DashboardWindow: View {
    static let windowID = "dashboard"

   
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var dns: DNSAutomationService
    @EnvironmentObject private var server: LocalServerController
    @EnvironmentObject private var runtimes: RuntimeManager
    @EnvironmentObject private var caTrust: CATrustService
    @EnvironmentObject private var updater: UpdaterController
    @EnvironmentObject private var uninstaller: UninstallService

    @State private var selection: SidebarItem = .sites

    @State private var logTarget: String?
    @StateObject private var overlay = KTOverlayCenter()


    private func openLogs(_ sourceID: String?) {
        logTarget = sourceID
        selection = .logs
    }

    var body: some View {
        KTDashboardShell(
            selection: $selection,
            siteCount: server.registry.sites.count,
            serverStatus: sidebarServerStatus,
            version: versionText) {
            DeferredView { detail(for: selection) }
                .id(selection)
        }
        .environmentObject(overlay)
        .overlay { windowModals }
        .animation(.easeOut(duration: 0.15), value: overlay.databaseEditorPresented)
        .animation(.easeOut(duration: 0.15), value: overlay.newSitePresented)
        .animation(.easeOut(duration: 0.15), value: overlay.connectPresented)
        .animation(.easeOut(duration: 0.15), value: overlay.newDatabasePresented)
        .ktOverlayHost(overlay)
    }

    @ViewBuilder
    private var windowModals: some View {
        if overlay.databaseEditorPresented {
            KTDatabaseEditorModal(onClose: { overlay.databaseEditorPresented = false })
                .transition(.opacity)
        }
        if overlay.newSitePresented {
            KTModalCard(icon: "plus.app", tint: KTIconTint.cube,
                        title: "New Site", subtitle: "Create a new local development site",
                        width: 680, onClose: { overlay.newSitePresented = false }) {
                KTNewSiteForm(registry: server.registry,
                              availableVersions: server.availableVersions,
                              sitesRoot: preferences.sitesRootURL, tld: server.registry.tld,
                              defaultHTTPS: preferences.serveHTTPSByDefault,
                              onClose: { overlay.newSitePresented = false })
            }
            .transition(.opacity)
        }
        if overlay.connectPresented {
            KTConnectModal(onClose: { overlay.connectPresented = false },
                           onConnected: { name in
                               overlay.connectPresented = false
                               overlay.toast("Connected to \(name)")
                           })
                .transition(.opacity)
        }
        if overlay.newDatabasePresented {
            KTNewDatabaseModal(onClose: { overlay.newDatabasePresented = false },
                               onCreated: { name in
                                   overlay.newDatabasePresented = false
                                   overlay.toast("Database “\(name)” created")
                               })
                .transition(.opacity)
        }
    }

    private var versionText: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var sidebarServerStatus: ServiceStatus {
        if server.nginxStatus == .starting || server.nginxStatus == .error || server.nginxStatus == .warning {
            return server.nginxStatus
        }
        return server.isRunning ? .running : .stopped
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .sites:    KTSitesScreen(onOpenLogs: openLogs)
        case .services: KTServicesScreen(onNavigate: { selection = $0 }, onOpenLogs: openLogs)
        case .runtimes: KTRuntimesScreen()
        case .logs:     LogsSectionView(targetSourceID: logTarget)
        case .mail:     MailSectionView()
        case .settings: SettingsView(preferences: preferences, dns: dns, server: server,
                                     runtimes: runtimes, caTrust: caTrust, updater: updater,
                                     uninstaller: uninstaller)
                            .navigationTitle("Settings")
        case .about:    AboutSettingsView().navigationTitle("About")
        case .database: KTDatabaseScreen()
        case .dumps:    DumpsPanelView()
        }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case manage, inspect, app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manage:  return "Manage"
        case .inspect: return "Inspect"
        case .app:     return "App"
        }
    }

    var items: [SidebarItem] {
        switch self {
        case .manage:  return [.sites, .services, .runtimes, .database]
        case .inspect: return [.logs, .mail, .dumps]
        case .app:     return [.settings, .about]
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case sites, services, runtimes, database, logs, mail, dumps, settings, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sites:    return "Sites"
        case .services: return "Services"
        case .runtimes: return "Runtimes"
        case .database: return "Database"
        case .logs:     return "Logs"
        case .mail:     return "Mail"
        case .dumps:    return "Dumps"
        case .settings: return "Settings"
        case .about:    return "About"
        }
    }

    var symbol: String {
        switch self {
        case .sites:    return "globe"
        case .services: return "server.rack"
        case .runtimes: return "cube"
        case .database: return "cylinder.split.1x2"
        case .logs:     return "text.alignleft"
        case .mail:     return "envelope"
        case .dumps:    return "curlybraces"
        case .settings: return "gearshape"
        case .about:    return "info.circle"
        }
    }
}
