import SwiftUI

public enum KTEditorTheme {
    public static let window = Color(hex: 0xFFFFFF)
    public static let content = Color(hex: 0xFFFFFF)
    public static let content2 = Color(hex: 0xF7F7FA)
    public static let sidebar = Color(hex: 0xFBFBFC)
    public static let separator = Color(hex: 0xECECF1)
    public static let separatorStrong = Color(hex: 0xE2E2E8)

    public static let titlebarTop = Color(hex: 0xFBFBFD)
    public static let titlebarBottom = Color(hex: 0xFFFFFF)

    public static let label = Color(hex: 0x1D1D1F)
    public static let label2 = Color(hex: 0x6B6B76)
    public static let label3 = Color(hex: 0x9A9AA5)
    public static let faint = Color(hex: 0xC0C0C8)

    public static let accent = Color(hex: 0x2F6BFF)
    public static let accentSoft = Color(hex: 0x2F6BFF, opacity: 0.10)
    public static let onAccent = Color(hex: 0xFFFFFF)

    public static let fieldBg = Color(hex: 0xF4F4F7)
    public static let fieldBorder = Color(hex: 0xEAEAEF)
    public static let btnBg = Color(hex: 0xFFFFFF)
    public static let btnBorder = Color(hex: 0xDCDCE3)
    public static let btnHover = Color(hex: 0xF7F7FA)
    public static let pillBg = Color(hex: 0xF0F0F3)
    public static let rowHover = Color(hex: 0xFAFAFC)
    public static let autocompleteBg = Color(hex: 0xFFFFFF)

    public static let switcherIcon = Color(hex: 0xF5961E)

    public enum Status {
        public static let running = Color(hex: 0x1FA463)
        public static let stopped = Color(hex: 0x9A9AA5)
        public static let warning = Color(hex: 0xB26A00)
        public static let error = Color(hex: 0xFF453A)
        public static let info = Color(hex: 0x5E5CE6)
    }

    public enum Syntax {
        public static let keyword = Color(hex: 0x0000FF)
        public static let function = Color(hex: 0x795E26)
        public static let string = Color(hex: 0xA31515)
        public static let number = Color(hex: 0x098658)
        public static let comment = Color(hex: 0x008000)
        public static let type = Color(hex: 0x267F99)
    }

    public enum Grid {
        public static let headerBg = Color(hex: 0xF7F7FA)
        public static let rownumBg = Color(hex: 0xFAFAFC)
        public static let cellText = Color(hex: 0x1D1D1F)
        public static let nullText = Color(hex: 0x9A9AA5)
        public static let number = Color(hex: 0xB26A00)
        public static let rowHover = Color(hex: 0xFAFAFC)
        public static let border = Color(hex: 0xECECF1)
        public static let editOutline = Color(hex: 0x2F6BFF)
        public static let editBg = Color(hex: 0x2F6BFF, opacity: 0.12)
    }
}
