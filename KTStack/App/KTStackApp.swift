import SwiftUI
import AppKit
import ServiceManagement
import KTStackKit

private struct MenuBarLaunchLabel: View {
    @Environment(\.openWindow) private var openWindow
    @State private var didLaunchWindow = false

    var body: some View {
        Image("MenuBarGlyph")
            .onAppear {
                guard !didLaunchWindow else { return }
                didLaunchWindow = true
                AppActivationPolicy.activateRegular()
                if !AppActivationPolicy.focusExistingWindow(titled: "KTStack Dashboard") {
                    openWindow(id: DashboardWindow.windowID)
                }
                DispatchQueue.main.async {
                    AppActivationPolicy.activateRegular()
                    AppActivationPolicy.resizeWindow(titled: "KTStack Dashboard", toFraction: 0.8)
                }
            }
    }
}

@main
struct KTStackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("KTStack.showInMenuBar") private var showInMenuBar = true

    init() {
        LegacyKDWarmMigration.runIfNeeded()
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
    }

    static var defaultWindowSize: CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: (visible.width * 0.8).rounded(), height: (visible.height * 0.8).rounded())
    }

    var body: some Scene {

        MenuBarExtra(isInserted: Binding(get: { showInMenuBar }, set: { _ in })) {
            MenuBarContentView()
                .environmentObject(appDelegate.server)
                .environmentObject(appDelegate.services)
                .environmentObject(appDelegate.runtimes)
                .environmentObject(appDelegate.updater)
        } label: {
            MenuBarLaunchLabel()
        }
        .menuBarExtraStyle(.window)

        
        Window("KTStack Dashboard", id: DashboardWindow.windowID) {
            DashboardWindow()
                .environmentObject(appDelegate.preferences)
                .environmentObject(appDelegate.server)
                .environmentObject(appDelegate.dns)
                .environmentObject(appDelegate.services)
                .environmentObject(appDelegate.runtimes)
                .environmentObject(appDelegate.mail)
                .environmentObject(appDelegate.caTrust)
                .environmentObject(appDelegate.updater)
                .environmentObject(appDelegate.uninstaller)
                .environmentObject(appDelegate.connectionStore)
                .environmentObject(appDelegate.databaseViewModel)
                .environmentObject(appDelegate.documentViewModel)
                .environmentObject(appDelegate.tunnels)
        }
        .defaultSize(width: Self.defaultWindowSize.width, height: Self.defaultWindowSize.height)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(preferences: appDelegate.preferences,
                         dns: appDelegate.dns,
                         server: appDelegate.server,
                         runtimes: appDelegate.runtimes,
                         caTrust: appDelegate.caTrust,
                         updater: appDelegate.updater,
                         uninstaller: appDelegate.uninstaller)
                .frame(width: 480, height: 560)   // the standalone Settings window's fixed size
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
   
    @MainActor lazy var preferences = AppPreferences()

 
    @MainActor lazy var server: LocalServerController = {
        LocalServerController(bundleBinDir: Self.bundleBinDir, tld: preferences.tld)
    }()

    @MainActor lazy var dns = DNSAutomationService(
        bundledDnsmasq: Self.bundleBinDir.appendingPathComponent("dnsmasq"),
        tld: preferences.tld)

    @MainActor lazy var services: ServiceManager = {
        let manager = ServiceManager(server: server, dns: dns)
        manager.startPolling()
        return manager
    }()

 
    @MainActor lazy var runtimes = RuntimeManager()

   
    @MainActor lazy var mail = MailStore()

    @MainActor lazy var updater = UpdaterController()

    @MainActor lazy var uninstaller = UninstallService(
        paths: AppSupportPaths(), dns: dns,
        mkcertBinary: Self.bundleBinDir.appendingPathComponent("mkcert"))

    @MainActor lazy var caTrust = CATrustService(
        paths: AppSupportPaths(), mkcertBinary: Self.bundleBinDir.appendingPathComponent("mkcert"))

    @MainActor lazy var connectionStore = ConnectionStore(
        storeURL: AppSupportPaths().config
            .appendingPathComponent("database", isDirectory: true)
            .appendingPathComponent("connections.json"))

    @MainActor lazy var databaseViewModel = DatabaseViewModel()

    @MainActor lazy var documentViewModel = DocumentViewModel()

    @MainActor lazy var tunnels = TunnelManager()

    private static func alreadyRunningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let current = NSRunningApplication.current
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != current.processIdentifier }
    }

    private static var bundleBinDir: URL {
        Bundle.main.resourceURL?.appendingPathComponent("bin", isDirectory: true)
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let existing = Self.alreadyRunningInstance() {
            existing.activate(options: [.activateAllWindows])
            exit(0)
        }

        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil)
        registerHelperIfSigned()

        _ = services
        refreshShellShim()
        tunnels.reapStaleJobs()
        server.onSitesChanged = { [tunnels] sites in tunnels.reconcile(sites: sites) }
        applyStartupPreferences()
    }

    @MainActor private func applyStartupPreferences() {
        if HelperIdentity.hasSigningIdentity { preferences.launchAtLogin = LoginItemService.isEnabled }
        updater.setAutomaticChecks(preferences.automaticUpdates)
        updater.setChannel(preferences.releaseChannel == .beta ? "beta" : "")
        if preferences.autoStartServer { services.startAll() }
    }

    
    private func refreshShellShim() {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ktstack-resolve")
        let manager = ShellPathManager(paths: AppSupportPaths(), helperSource: helper)
        do { try manager.refreshStagedShimIfEnabled() }
        catch { NSLog("KTStack: shell shim refresh skipped — \(error.localizedDescription)") }
    }

    private func registerHelperIfSigned() {
        guard HelperIdentity.hasSigningIdentity else {
            NSLog("KTStack: SMAppService helper registration deferred (no signing identity).")
            return
        }
        if #available(macOS 13.0, *) {
            do { try SMAppService.daemon(plistName: "com.ktstack.helper.plist").register() }
            catch { NSLog("KTStack: helper registration failed: \(error.localizedDescription)") }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {

        let dbShutdown = DispatchSemaphore(value: 0)
        Task.detached {
            try? await EventLoopProvider.shared.shutdown()
            dbShutdown.signal()
        }
        dbShutdown.wait()
       
        MainActor.assumeIsolated {
            tunnels.shutdownAll()
            server.shutdownForQuit()
        }
    }

    @objc private func windowWillClose(_ note: Notification) {

        let closingWindow = note.object as? NSWindow
        DispatchQueue.main.async {
            AppActivationPolicy.restoreAccessoryIfNoWindows(excluding: closingWindow)
        }
    }
}
