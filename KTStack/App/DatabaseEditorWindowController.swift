import AppKit
import SwiftUI
import KTStackKit

@MainActor
final class DatabaseEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = DatabaseEditorWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    func present(env: DashboardEnv) {
        AppActivationPolicy.activateRegular()

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = env.inject(KTDatabaseEditorRoot(onClose: { [weak self] in self?.close() }))
        let hosting = NSHostingController(rootView: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "SQL Editor"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 900, height: 560)
        window.setFrameAutosaveName("KTStackSQLEditor")
        if window.frame.width < 900 || window.frame.height < 560 {
            window.setContentSize(NSSize(width: 1200, height: 760))
            window.center()
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
