import SwiftUI
import AppKit
import ServiceManagement
import KTStackKit

@main
struct KTStackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        LegacyKDWarmMigration.runIfNeeded()
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
    }

    var body: some Scene {
        
        MenuBarExtra("KTStack", image: "MenuBarGlyph") {
            MenuBarContentView()
                .environmentObject(appDelegate.server)
                .environmentObject(appDelegate.services)
                .environmentObject(appDelegate.runtimes)
                .environmentObject(appDelegate.updater)
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
        .defaultSize(width: 920, height: 600)
        .windowResizability(.contentMinSize)

        Window("Database", id: DatabaseWindow.windowID) {
            DatabaseWindow()
                .environmentObject(appDelegate.services)
                .environmentObject(appDelegate.connectionStore)
                .environmentObject(appDelegate.databaseViewModel)
                .environmentObject(appDelegate.documentViewModel)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(preferences: appDelegate.preferences,
                         dns: appDelegate.dns,
                         server: appDelegate.server,
                         caTrust: appDelegate.caTrust,
                         updater: appDelegate.updater,
                         uninstaller: appDelegate.uninstaller)
                .frame(width: 480, height: 360)   // the standalone Settings window's fixed size
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
        tunnels.reapStaleJobs()
        server.onSitesChanged = { [tunnels] sites in tunnels.reconcile(sites: sites) }
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
