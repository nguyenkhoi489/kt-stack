import KTStackKit
import SwiftUI

enum V2ButtonKind {
    case primary
    case standard
    case danger
}

struct V2Button: View {
    let title: String
    var systemImage: String?
    var kind: V2ButtonKind = .standard
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11))
                }
                Text(title).font(.system(size: 12.5, weight: kind == .primary ? .semibold : .regular))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                if kind != .primary {
                    RoundedRectangle(cornerRadius: 7).stroke(borderColor, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch kind {
        case .primary: KTEditorTheme.onAccent
        case .standard: KTEditorTheme.label
        case .danger: KTEditorTheme.Status.error
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        switch kind {
        case .primary:
            AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0x4385FF), KTEditorTheme.accent],
                startPoint: .top, endPoint: .bottom
            ))
        default:
            AnyShapeStyle(KTEditorTheme.btnBg)
        }
    }

    private var borderColor: Color {
        kind == .danger
            ? KTEditorTheme.Status.error.opacity(0.4)
            : KTEditorTheme.btnBorder
    }
}

struct V2IconButton: View {
    let systemImage: String
    var tint: Color = KTEditorTheme.label2
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 28, height: 26)
        }
        .buttonStyle(.plain)
    }
}
