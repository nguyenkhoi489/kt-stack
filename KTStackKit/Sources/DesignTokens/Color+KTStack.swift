import AppKit
import SwiftUI

public extension Color {
    enum KDStatus {
        public static let running = Color(kdLight: 0x1FAD66, dark: 0x30D158)
        public static let stopped = Color(kdLight: 0x8A8A8E, dark: 0x98989D)
        public static let starting = Color(kdLight: 0x0A84FF, dark: 0x0A84FF)
        public static let warning = Color(kdLight: 0xFF9F0A, dark: 0xFF9F0A)
        public static let error = Color(kdLight: 0xFF453A, dark: 0xFF453A)
        public static let info = Color(kdLight: 0x5E5CE6, dark: 0x5E5CE6)
    }
}

extension Color {
    init(kdLight light: UInt32, dark: UInt32) {
        let dynamic = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(kdRGB: isDark ? dark : light)
        }
        self.init(nsColor: dynamic)
    }
}

private extension NSColor {
    convenience init(kdRGB rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
