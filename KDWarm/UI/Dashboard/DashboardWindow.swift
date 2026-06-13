import SwiftUI
import KDWarmKit

/// Dashboard shell: a `NavigationSplitView` whose sidebar is driven by `SidebarItem`
/// and whose detail switches to one of the six section views (design-guidelines §5.6).
struct DashboardWindow: View {
    static let windowID = "dashboard"

    // Forwarded into the in-dashboard Settings pane (env-object lookup is reliable in a Window scene).
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var dns: DNSAutomationService
    @EnvironmentObject private var server: LocalServerController
    @EnvironmentObject private var caTrust: CATrustService
    @EnvironmentObject private var updater: UpdaterController
    @EnvironmentObject private var uninstaller: UninstallService

    @State private var selection: SidebarItem? = .sites
    /// Deep-link target for the Logs view (a `LogSource.id`) set by a Services/Sites "Logs" action.
    @State private var logTarget: String?

    /// Jump to the Logs view, optionally preselecting a source.
    private func openLogs(_ sourceID: String?) {
        logTarget = sourceID
        selection = .logs
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            detail(for: selection ?? .sites)
        }
        .frame(minWidth: 720, minHeight: 460)
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .sites:    SitesSectionView(onOpenLogs: openLogs)
        case .services: ServicesSectionView(onNavigate: { selection = $0 }, onOpenLogs: openLogs)
        case .runtimes: RuntimesSectionView()
        case .logs:     LogsSectionView(targetSourceID: logTarget)
        case .mail:     MailSectionView()
        case .settings: SettingsView(preferences: preferences, dns: dns, server: server,
                                     caTrust: caTrust, updater: updater, uninstaller: uninstaller)
                            .navigationTitle("Settings")
        case .about:    AboutSettingsView().navigationTitle("About")
        }
    }
}

/// Top-level dashboard destinations (design-guidelines §5.6).
enum SidebarItem: String, CaseIterable, Identifiable {
    case sites, services, runtimes, logs, mail, settings, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sites:    return "Sites"
        case .services: return "Services"
        case .runtimes: return "Runtimes"
        case .logs:     return "Logs"
        case .mail:     return "Mail"
        case .settings: return "Settings"
        case .about:    return "About"
        }
    }

    var symbol: String {
        switch self {
        case .sites:    return "globe"
        case .services: return "server.rack"
        case .runtimes: return "cpu"
        case .logs:     return "text.alignleft"
        case .mail:     return "envelope"
        case .settings: return "gearshape"
        case .about:    return "info.circle"
        }
    }
}
