import SwiftUI

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

public enum KTColor {
    public static let accent = Color(hex: 0x2F6BFF)
    public static let accentTop = Color(hex: 0x4385FF)
    public static let accentSoft = Color(hex: 0x2F6BFF, opacity: 0.10)
    public static let accentGradient = LinearGradient(
        colors: [Color(hex: 0x4385FF), Color(hex: 0x2F6BFF)],
        startPoint: .top, endPoint: .bottom
    )

    public static let ink = Color(hex: 0x1D1D1F)
    public static let ink2 = Color(hex: 0x42424C)
    public static let ink3 = Color(hex: 0x6B6B76)
    public static let muted = Color(hex: 0x9A9AA5)
    public static let faint = Color(hex: 0xC0C0C8)

    public static let contentBg = Color.white
    public static let sidebarBg = Color(hex: 0xF8F8FB, opacity: 0.82)
    public static let rowHover = Color(hex: 0xFAFAFC)

    public static let sep = Color(hex: 0xECECF1)
    public static let sepFaint = Color(hex: 0xF2F2F5)
    public static let hairline = Color(hex: 0xF9F9FC)
    public static let sidebarBackground = Color(hex: 0xF9F9FC)

    public static let fieldBg = Color(hex: 0xF4F4F7)
    public static let fieldBorder = Color(hex: 0xEAEAEF)
    public static let fieldBorderStrong = Color(hex: 0xE2E2E8)

    public static let pillBg = Color(hex: 0xF0F0F3)
    public static let segmentBg = Color(hex: 0xF0F0F3)
    public static let btnBorder = Color(hex: 0xDCDCE3)
    public static let btnHover = Color(hex: 0xF7F7FA)
    public static let menuHover = Color(hex: 0x2F6BFF, opacity: 0.10)

    public static let runDot = Color(hex: 0x34C759)
    public static let stopDot = Color(hex: 0xC7C7CC)
    public static let runText = Color(hex: 0x1D1D1F)
    public static let stopText = Color(hex: 0x9A9AA5)
    public static let online = Color(hex: 0x1FA463)
    public static let onlineBg = Color(hex: 0xE7F8EE)

    public static let danger = Color(hex: 0xFF453A)
    public static let dangerBg = Color(hex: 0xFFF5F4)
    public static let dangerBorder = Color(hex: 0xFFD4D0)

    public static let editorBg = Color(hex: 0x14141A)
    public static let modalScrim = Color(hex: 0x140F28, opacity: 0.32)
}

public struct KTTint: Sendable, Hashable {
    public let fg: Color
    public let bg: Color
    public init(fg: Color, bg: Color) {
        self.fg = fg; self.bg = bg
    }
}

public enum KTIconTint {
    public static let code = KTTint(fg: Color(hex: 0x2F6BFF), bg: Color(hex: 0xEAF1FF))
    public static let cube = KTTint(fg: Color(hex: 0x8B5CF6), bg: Color(hex: 0xF1ECFF))
    public static let db = KTTint(fg: Color(hex: 0xF5961E), bg: Color(hex: 0xFFF1E0))
    public static let globe = KTTint(fg: Color(hex: 0x1FA463), bg: Color(hex: 0xE7F8EE))
    public static let mail = KTTint(fg: Color(hex: 0xE0467C), bg: Color(hex: 0xFFEDF3))
    public static let neutral = KTTint(fg: Color(hex: 0x86868F), bg: Color(hex: 0xEFEFF3))
    public static let wordpress = KTTint(fg: Color(hex: 0x1E6A8D), bg: Color(hex: 0xE3F1F8))
    public static let laravel = KTTint(fg: Color(hex: 0xD8412F), bg: Color(hex: 0xFDE9E6))
    public static let php = KTTint(fg: Color(hex: 0x6C72B8), bg: Color(hex: 0xECEDF8))
}

public enum KTEngineTint {
    public static func of(_ engine: String) -> KTTint {
        switch engine.lowercased() {
        case "postgresql", "postgres", "pg":
            KTTint(fg: Color(hex: 0x2F6BFF), bg: Color(hex: 0xEAF1FF))
        case "mongodb", "mongo":
            KTTint(fg: Color(hex: 0x13AA52), bg: Color(hex: 0xE5F7EC))
        case "sqlite":
            KTTint(fg: Color(hex: 0x5C6B7A), bg: Color(hex: 0xEEF0F4))
        default:
            KTTint(fg: Color(hex: 0x1FA463), bg: Color(hex: 0xE7F8EE))
        }
    }
}
