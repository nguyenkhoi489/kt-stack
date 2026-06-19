import SwiftUI
import KTStackKit

enum KTButtonKind {
    case primary, secondary, danger
}

struct KTButton: View {
    let title: String
    var systemImage: String?
    var kind: KTButtonKind = .secondary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(.system(size: 13, weight: weight))
            }
            .foregroundStyle(foreground)
            .padding(.vertical, kind == .primary ? 9 : 8)
            .padding(.horizontal, 14)
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: KTRadius.button, style: .continuous))
            .shadow(color: shadowColor, radius: kind == .primary ? 6 : 0, x: 0, y: kind == .primary ? 2 : 0)
            .brightness(hovering && kind == .primary ? 0.04 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var weight: Font.Weight { kind == .secondary ? .medium : .semibold }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return KTColor.ink
        case .danger: return KTColor.danger
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary: KTColor.accentGradient
        case .secondary: (hovering ? KTColor.btnHover : Color.white)
        case .danger: (hovering ? KTColor.dangerBg : Color.white)
        }
    }

    @ViewBuilder private var border: some View {
        switch kind {
        case .primary: EmptyView()
        case .secondary:
            RoundedRectangle(cornerRadius: KTRadius.button, style: .continuous)
                .strokeBorder(KTColor.btnBorder, lineWidth: 0.5)
        case .danger:
            RoundedRectangle(cornerRadius: KTRadius.button, style: .continuous)
                .strokeBorder(KTColor.dangerBorder, lineWidth: 0.5)
        }
    }

    private var shadowColor: Color {
        kind == .primary ? KTColor.accent.opacity(0.5) : .clear
    }
}
