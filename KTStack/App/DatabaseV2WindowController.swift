import AppKit
import KTStackKit
import SwiftUI

@MainActor
final class DatabaseV2WindowController: NSObject, NSWindowDelegate {
    static let shared = DatabaseV2WindowController()

    private var window: NSWindow?
    private lazy var viewModel = DatabaseV2ViewModel()

    override private init() {
        super.init()
    }

    func present(profile: ConnectionProfile) {
        AppActivationPolicy.activateRegular()

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            Task { await self.viewModel.connect(profile: profile) }
            return
        }

        let root = DatabaseV2Root(vm: viewModel, onClose: { [weak self] in self?.close() })
        let hosting = NSHostingController(rootView: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.contentViewController = hosting
        window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "SQL Editor"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 900, height: 560)
        window.setFrameAutosaveName("KTStackSQLEditorV2")
        if window.frame.width < 900 || window.frame.height < 560 {
            window.setContentSize(NSSize(width: 1200, height: 760))
            window.center()
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        Task { await self.viewModel.connect(profile: profile) }
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_: Notification) {
        let vm = viewModel
        window = nil
        Task { await vm.disconnect() }
    }
}
