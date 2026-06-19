import SwiftUI
import KTStackKit

struct KTPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Color(hex: 0x8E8E93))
            .padding(.vertical, 3)
            .padding(.horizontal, 10)
            .background(Capsule().fill(KTColor.pillBg))
    }
}

struct KTBadge: View {
    let text: String
    let tint: KTTint
    var radius: CGFloat = 6

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(tint.fg)
            .padding(.vertical, 3)
            .padding(.horizontal, 9)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint.bg))
    }
}
