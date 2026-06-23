import SwiftUI
import KTStackKit


struct DashboardWindow: View {
    static let windowID = "dashboard"

   
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var dns: DNSAutomationService
    @EnvironmentObject private var server: LocalServerController
    @EnvironmentObject private var services: ServiceManager
    @EnvironmentObject private var runtimes: RuntimeManager
    @EnvironmentObject private var mail: MailStore
    @EnvironmentObject private var caTrust: CATrustService
    @EnvironmentObject private var updater: UpdaterController
    @EnvironmentObject private var uninstaller: UninstallService
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var databaseViewModel: DatabaseViewModel
    @EnvironmentObject private var documentViewModel: DocumentViewModel
    @EnvironmentObject private var tunnels: TunnelManager

    @StateObject private var nav = DashboardNavigation()
    @StateObject private var overlay = KTOverlayCenter()

    private var dashboardEnv: DashboardEnv {
        DashboardEnv(preferences: preferences, server: server, dns: dns, services: services,
                     runtimes: runtimes, mail: mail, caTrust: caTrust, updater: updater,
                     uninstaller: uninstaller, connectionStore: connectionStore,
                     databaseViewModel: databaseViewModel, documentViewModel: documentViewModel,
                     tunnels: tunnels, overlay: overlay)
    }

    var body: some View {
        DashboardSplitRepresentable(nav: nav, env: dashboardEnv)
            .frame(minWidth: 720, minHeight: 460)
            .environmentObject(overlay)
            .ktOverlayHost(overlay)
            .ignoresSafeArea(.container, edges: .top)
            .background(KTWindowChrome())
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
