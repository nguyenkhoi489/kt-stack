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
