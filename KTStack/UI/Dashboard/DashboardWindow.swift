import SwiftUI
import KTStackKit


struct DashboardWindow: View {
    static let windowID = "dashboard"

   
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var dns: DNSAutomationService
    @EnvironmentObject private var server: LocalServerController
    @EnvironmentObject private var caTrust: CATrustService
    @EnvironmentObject private var updater: UpdaterController
    @EnvironmentObject private var uninstaller: UninstallService

    @State private var selection: SidebarItem = .sites

    @State private var logTarget: String?


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
            detail(for: selection)
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
                                     caTrust: caTrust, updater: updater, uninstaller: uninstaller)
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
