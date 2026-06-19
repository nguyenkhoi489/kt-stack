import SwiftUI
import KTStackKit

struct KTEngineCard: View {
    let name: String
    let tint: KTTint
    let active: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                KTIconTile(tint: tint, size: 30, radius: 8) {
                    Image(systemName: "cylinder.split.1x2").font(.system(size: 14, weight: .medium))
                }
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KTColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(active ? KTColor.accentSoft : (hovering ? KTColor.btnHover : Color.white)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(active ? KTColor.accent : Color(hex: 0xE6E6EC), lineWidth: active ? 1.5 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
