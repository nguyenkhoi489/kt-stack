import AppKit
import KTStackKit
import SwiftUI

@MainActor
final class DocumentWindowController: NSObject, NSWindowDelegate {
    static let shared = DocumentWindowController()

    private var window: NSWindow?

    override private init() {
        super.init()
    }

    func present(documentVM: DocumentViewModel, services: ServiceManager) {
        AppActivationPolicy.activateRegular()

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let root = DocumentSectionContent()
            .environmentObject(documentVM)
            .environmentObject(services)
        let hosting = NSHostingController(rootView: root)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.contentViewController = hosting
        w.appearance = NSAppearance(named: .aqua)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Document Browser"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentMinSize = NSSize(width: 720, height: 480)
        w.setFrameAutosaveName("KTStackDocumentEditor")
        if w.frame.width < 720 || w.frame.height < 480 {
            w.setContentSize(NSSize(width: 1000, height: 680))
            w.center()
        }

        self.window = w
        w.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_: Notification) {
        window = nil
    }
}
