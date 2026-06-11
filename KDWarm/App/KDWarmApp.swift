import SwiftUI
import AppKit
import ServiceManagement
import KDWarmKit

@main
struct KDWarmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar entry. `.window` style gives a real SwiftUI canvas so status pills
        // and toggles render per the design (a plain `.menu` cannot host them).
        MenuBarExtra("KDWarm", image: "MenuBarGlyph") {
            MenuBarContentView()
                .environmentObject(appDelegate.server)
                .environmentObject(appDelegate.services)
                .environmentObject(appDelegate.runtimes)
                .environmentObject(appDelegate.updater)
        }
        .menuBarExtraStyle(.window)

        // Dashboard window, opened on demand from the menu-bar footer.
        Window("KDWarm Dashboard", id: DashboardWindow.windowID) {
            DashboardWindow()
                .environmentObject(appDelegate.server)
                .environmentObject(appDelegate.dns)
                .environmentObject(appDelegate.services)
                .environmentObject(appDelegate.runtimes)
                .environmentObject(appDelegate.mail)
        }
        .defaultSize(width: 920, height: 600)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.caTrust)
                .environmentObject(appDelegate.updater)
                .environmentObject(appDelegate.uninstaller)
        }
    }
}

/// Owns the accessory-app launch posture and restores it as windows close.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The live nginx + php-fpm orchestrator, shared with the menu bar and dashboard.
    /// Binaries are staged from the bundle's `Resources/bin` into app-support on first start.
    @MainActor lazy var server: LocalServerController = {
        LocalServerController(bundleBinDir: Self.bundleBinDir)
    }()

    /// `.test` DNS automation (helper when signed; sudo fallback otherwise).
    @MainActor lazy var dns = DNSAutomationService(
        bundledDnsmasq: Self.bundleBinDir.appendingPathComponent("dnsmasq"))

    /// Aggregates all services (nginx/php-fpm via the server; DBs/Mailpit/dnsmasq) for the Services
    /// view + menu bar, polling their health sub-second.
    @MainActor lazy var services: ServiceManager = {
        let manager = ServiceManager(server: server, dns: dns)
        manager.startPolling()
        return manager
    }()

    /// Runtime versions: bundled PHP (staged into runtimes/) + on-demand Node/Python/Go downloads.
    @MainActor lazy var runtimes = RuntimeManager()

    /// Mailpit message store for the Mail catcher view (polls the local Mailpit REST API).
    @MainActor lazy var mail = MailStore()

    /// Sparkle auto-updater (background appcast checks + manual "Check for Updates…").
    @MainActor lazy var updater = UpdaterController()

    /// Full uninstall / reset orchestrator (Settings → Uninstall).
    @MainActor lazy var uninstaller = UninstallService(
        paths: AppSupportPaths(), dns: dns,
        mkcertBinary: Self.bundleBinDir.appendingPathComponent("mkcert"))

    /// Local root CA trust (mkcert) for HTTPS `*.test`.
    @MainActor lazy var caTrust = CATrustService(
        paths: AppSupportPaths(), mkcertBinary: Self.bundleBinDir.appendingPathComponent("mkcert"))

    private static var bundleBinDir: URL {
        Bundle.main.resourceURL?.appendingPathComponent("bin", isDirectory: true)
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as a menu-bar-only accessory: no Dock icon, no default window.
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil)
        registerHelperIfSigned()
        // Touch the service manager so its health poll starts immediately — this also reattaches the
        // status of any launchd services left running by a previous session.
        _ = services
    }

    /// Register the SMAppService daemon — but only on a real signed build. The dev/ad-hoc build
    /// has no Team ID, so the daemon can't be trusted/approved; DNS uses the sudo fallback there.
    /// Live registration + the approval flow are validated in Phase 9 (signing/notarization).
    private func registerHelperIfSigned() {
        guard HelperIdentity.hasSigningIdentity else {
            NSLog("KDWarm: SMAppService helper registration deferred (no signing identity).")
            return
        }
        if #available(macOS 13.0, *) {
            do { try SMAppService.daemon(plistName: "com.kdwarm.helper.plist").register() }
            catch { NSLog("KDWarm: helper registration failed: \(error.localizedDescription)") }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Services are launchd-managed and PERSIST across app quit (the app is a controller, not the
        // process parent), so we deliberately do NOT stop nginx/php-fpm here — only the in-process
        // folder watcher. Bringing everything down is the explicit "Stop all" action.
        MainActor.assumeIsolated { server.shutdownForQuit() }
    }

    @objc private func windowWillClose(_ note: Notification) {
        // Defer until after the window is gone, then drop back to accessory if no
        // ordinary windows remain — excluding the window that is closing now.
        let closingWindow = note.object as? NSWindow
        DispatchQueue.main.async {
            AppActivationPolicy.restoreAccessoryIfNoWindows(excluding: closingWindow)
        }
    }
}
