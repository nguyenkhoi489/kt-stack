import SwiftUI
import AppKit
import KTStackKit

struct DashboardEnv {
    let preferences: AppPreferences
    let server: LocalServerController
    let dns: DNSAutomationService
    let services: ServiceManager
    let runtimes: RuntimeManager
    let mail: MailStore
    let caTrust: CATrustService
    let updater: UpdaterController
    let uninstaller: UninstallService
    let connectionStore: ConnectionStore
    let databaseViewModel: DatabaseViewModel
    let documentViewModel: DocumentViewModel
    let tunnels: TunnelManager
    let overlay: KTOverlayCenter

    func inject<V: View>(_ view: V) -> some View {
        view
            .environmentObject(preferences)
            .environmentObject(server)
            .environmentObject(dns)
            .environmentObject(services)
            .environmentObject(runtimes)
            .environmentObject(mail)
            .environmentObject(caTrust)
            .environmentObject(updater)
            .environmentObject(uninstaller)
            .environmentObject(connectionStore)
            .environmentObject(databaseViewModel)
            .environmentObject(documentViewModel)
            .environmentObject(tunnels)
            .environmentObject(overlay)
    }
}

struct DashboardSplitRepresentable: NSViewControllerRepresentable {
    @ObservedObject var nav: DashboardNavigation
    let env: DashboardEnv

    func makeNSViewController(context: Context) -> DashboardSplitViewController {
        DashboardSplitViewController(nav: nav, env: env)
    }

    func updateNSViewController(_ controller: DashboardSplitViewController, context: Context) {
        controller.show(nav.selection)
    }
}

private struct DashboardSidebarHost: View {
    @ObservedObject var nav: DashboardNavigation
    @EnvironmentObject private var server: LocalServerController

    var body: some View {
        KTSidebar(
            selection: Binding(get: { nav.selection }, set: { nav.selection = $0 }),
            siteCount: server.registry.sites.count,
            serverStatus: serverStatus,
            version: versionText)
            .ignoresSafeArea(.container, edges: .top)
    }

    private var serverStatus: ServiceStatus {
        if server.nginxStatus == .starting || server.nginxStatus == .error || server.nginxStatus == .warning {
            return server.nginxStatus
        }
        return server.isRunning ? .running : .stopped
    }

    private var versionText: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}

final class DashboardSplitViewController: NSSplitViewController {
    private let nav: DashboardNavigation
    private let env: DashboardEnv
    private let detailContainer: DetailContainerViewController

    init(nav: DashboardNavigation, env: DashboardEnv) {
        self.nav = nav
        self.env = env
        self.detailContainer = DetailContainerViewController(nav: nav, env: env)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarController = NSHostingController(rootView: env.inject(DashboardSidebarHost(nav: nav)))
        let sidebarItem = NSSplitViewItem(viewController: sidebarController)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = KTMetric.sidebarWidth
        sidebarItem.maximumThickness = KTMetric.sidebarWidth

        let detailItem = NSSplitViewItem(viewController: detailContainer)
        detailItem.canCollapse = false

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)

        splitView.dividerStyle = .thin
        detailContainer.show(nav.selection)
    }

    func show(_ item: SidebarItem) {
        detailContainer.show(item)
    }
}

final class DetailContainerViewController: NSViewController {
    private let nav: DashboardNavigation
    private let env: DashboardEnv
    private var cache: [SidebarItem: NSHostingController<AnyView>] = [:]
    private var current: SidebarItem?

    init(nav: DashboardNavigation, env: DashboardEnv) {
        self.nav = nav
        self.env = env
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        view = container
    }

    func show(_ item: SidebarItem) {
        if current == item { return }

        let controller = cache[item] ?? makeController(item)
        cache[item] = controller

        if let previous = current, let previousController = cache[previous] {
            view.window?.makeFirstResponder(nil)
            previousController.view.isHidden = true
        }

        if controller.parent == nil {
            addChild(controller)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(controller.view)
            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: view.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        }

        controller.view.isHidden = false
        current = item
        DispatchQueue.main.async { [nav] in nav.activeItem = item }
    }

    private func makeController(_ item: SidebarItem) -> NSHostingController<AnyView> {
        let content = VStack(spacing: 0) {
            Color.clear.frame(height: KTMetric.trafficLightInset - 18)
            detailView(for: item)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KTColor.contentBg)
        .ignoresSafeArea(.container, edges: .top)

        return NSHostingController(rootView: AnyView(env.inject(content)))
    }

    @ViewBuilder
    private func detailView(for item: SidebarItem) -> some View {
        let nav = self.nav
        switch item {
        case .sites:
            KTSitesScreen(onOpenLogs: { nav.openLogs($0) }, onNavigate: { nav.selection = $0 })
        case .services:
            KTServicesScreen(onNavigate: { nav.selection = $0 }, onOpenLogs: { nav.openLogs($0) })
        case .runtimes:
            KTRuntimesScreen()
        case .logs:
            LogsSectionView(nav: nav)
        case .mail:
            MailSectionView(nav: nav)
        case .settings:
            SettingsView(preferences: env.preferences, dns: env.dns, server: env.server,
                         runtimes: env.runtimes, caTrust: env.caTrust, updater: env.updater,
                         uninstaller: env.uninstaller)
                .navigationTitle("Settings")
        case .about:
            AboutSettingsView().navigationTitle("About")
        case .database:
            KTDatabaseScreen()
        case .dumps:
            DumpsPanelView()
        }
    }
}
