import KTStackKit
import SwiftUI

struct KTSidebarRow: View {
    let item: SidebarItem
    let isActive: Bool
    let badge: Int?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 18, height: 18)
                Text(item.title)
                    .font(.jbMono(13.5, isActive ? .regular : .medium))
                Spacer(minLength: 6)
                if let badge {
                    Text("\(badge)")
                        .font(.jbMono(11.5, .regular))
                        .foregroundStyle(isActive ? KTColor.accent : KTColor.muted)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 7)
                        .background(Capsule().fill(isActive ? KTColor.accentSoft : KTColor.pillBg))
                }
            }
            .foregroundStyle(isActive ? KTColor.accent : KTColor.ink2)
            .padding(.vertical, 8)
            .padding(.horizontal, 11)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? KTColor.accentSoft : (hovering ? Color.black.opacity(0.045) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
