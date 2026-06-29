import AppKit

enum AppActivationPolicy {
    static func activateRegular() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult
    static func focusExistingWindow(titled title: String) -> Bool {
        guard let window = NSApp.windows.first(where: {
            $0.title == title && $0.canBecomeMain && !($0 is NSPanel)
        }) else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    static func resizeWindow(titled title: String, toFraction fraction: CGFloat) {
        guard let screen = NSScreen.main,
              let window = NSApp.windows.first(where: { $0.title == title && !($0 is NSPanel) })
        else { return }
        let visible = screen.visibleFrame
        let width = (visible.width * fraction).rounded()
        let height = (visible.height * fraction).rounded()
        let origin = NSPoint(
            x: visible.minX + (visible.width - width) / 2,
            y: visible.minY + (visible.height - height) / 2
        )
        window.setFrame(
            NSRect(origin: origin, size: NSSize(width: width, height: height)),
            display: true,
            animate: false
        )
    }

    static func restoreAccessoryIfNoWindows(excluding closingWindow: NSWindow? = nil) {
        let hasOrdinaryWindow = NSApp.windows.contains { window in
            window !== closingWindow
                && window.isVisible
                && window.canBecomeMain
                && !(window is NSPanel)
        }
        if !hasOrdinaryWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
