import AppKit
import Combine
import KTStackKit
import SwiftUI

struct KTWindowModals: View {
    @EnvironmentObject private var server: LocalServerController
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var overlay: KTOverlayCenter

    var body: some View {
        ZStack {
            if overlay.newSitePresented {
                KTModalCard(
                    icon: "plus.app",
                    tint: KTIconTint.cube,
                    title: "New Site",
                    subtitle: "Create a new site or import an existing folder",
                    width: 680,
                    onClose: { overlay.newSitePresented = false }
                ) {
                    KTNewSiteForm(
                        registry: server.registry,
                        availableVersions: server.availableVersions,
                        sitesRoot: preferences.sitesRootURL,
                        tld: server.registry.tld,
                        defaultHTTPS: preferences.serveHTTPSByDefault,
                        onClose: { overlay.newSitePresented = false }
                    )
                }
                .transition(.opacity)
            }
            if overlay.connectPresented {
                KTConnectModal(
                    onClose: { overlay.connectPresented = false },
                    onConnected: { name in
                        overlay.connectPresented = false
                        overlay.toast("Connected to \(name)")
                    }
                )
                .transition(.opacity)
            }
            if overlay.newDatabasePresented {
                KTNewDatabaseModal(
                    onClose: { overlay.newDatabasePresented = false },
                    onCreated: { name in
                        overlay.newDatabasePresented = false
                        overlay.toast("Database “\(name)” created")
                    }
                )
                .transition(.opacity)
            }
            if let site = overlay.apiTesterSite {
                KTAPITesterModal(site: site, onClose: { overlay.apiTesterSite = nil })
                    .id(site.id)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: overlay.newSitePresented)
        .animation(.easeOut(duration: 0.15), value: overlay.connectPresented)
        .animation(.easeOut(duration: 0.15), value: overlay.newDatabasePresented)
        .animation(.easeOut(duration: 0.15), value: overlay.apiTesterSite?.id)
    }
}

final class KTKeyableModalWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class KTModalHostController {
    private let overlay: KTOverlayCenter
    private weak var parentWindow: NSWindow?
    private let window: KTKeyableModalWindow
    private var cancellables: Set<AnyCancellable> = []
    private var isShown = false

    init(parent: NSWindow, env: DashboardEnv) {
        overlay = env.overlay
        parentWindow = parent

        window = KTKeyableModalWindow(
            contentRect: parent.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentView = NSHostingView(rootView: AnyView(env.inject(KTWindowModals())))

        observe()
        syncPresentation()
    }

    private func observe() {
        overlay.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.syncPresentation() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: parentWindow)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: parentWindow))
            .sink { [weak self] _ in
                guard let self, isShown else { return }
                syncFrame()
            }
            .store(in: &cancellables)
    }

    private func syncPresentation() {
        overlay.anyModalPresented ? show() : hide()
    }

    private func syncFrame() {
        guard let parentWindow else { return }
        window.setFrame(parentWindow.frame, display: true)
    }

    private func show() {
        guard !isShown, let parentWindow else { return }
        isShown = true
        syncFrame()
        if window.parent == nil { parentWindow.addChildWindow(window, ordered: .above) }
        syncFrame()
        window.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        guard isShown else { return }
        isShown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, !self.isShown, !self.overlay.anyModalPresented else { return }
            parentWindow?.removeChildWindow(window)
            window.orderOut(nil)
            parentWindow?.makeKeyAndOrderFront(nil)
        }
    }
}
