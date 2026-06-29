#if DEBUG
    import AppKit
    import SwiftUI

    @MainActor
    final class SQLEditorDraftsWindowController: NSObject, NSWindowDelegate {
        static let shared = SQLEditorDraftsWindowController()

        private var window: NSWindow?

        override private init() {
            super.init()
        }

        func present() {
            AppActivationPolicy.activateRegular()

            if let window {
                window.makeKeyAndOrderFront(nil)
                return
            }

            let hosting = NSHostingController(rootView: SQLEditorDraftsGallery())

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.contentViewController = hosting
            window.appearance = NSAppearance(named: .aqua)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "SQL Editor Drafts"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentMinSize = NSSize(width: 900, height: 560)
            window.setFrameAutosaveName("KTStackSQLEditorDrafts")
            if window.frame.width < 900 || window.frame.height < 560 {
                window.setContentSize(NSSize(width: 1200, height: 760))
                window.center()
            }

            self.window = window
            window.makeKeyAndOrderFront(nil)
        }

        func windowWillClose(_: Notification) {
            window = nil
        }
    }

#endif
