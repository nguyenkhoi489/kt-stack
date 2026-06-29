#if DEBUG
    import KTStackKit
    import SwiftUI

    enum DraftButtonKind {
        case primary
        case standard
        case danger
    }

    struct DraftButton: View {
        let title: String
        var systemImage: String?
        var shortcut: String?
        var kind: DraftButtonKind = .standard

        var body: some View {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 11)) }
                Text(title).font(.system(size: 12.5, weight: kind == .primary ? .semibold : .regular))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10))
                        .foregroundStyle(kind == .primary ? Color.white.opacity(0.85) : KTEditorTheme.label2)
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(borderTint, lineWidth: 1))
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                if kind != .primary {
                    RoundedRectangle(cornerRadius: 7).stroke(KTEditorTheme.btnBorder, lineWidth: 1)
                }
            }
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
                    startPoint: .top,
                    endPoint: .bottom
                ))
            default:
                AnyShapeStyle(KTEditorTheme.btnBg)
            }
        }

        private var borderTint: Color {
            kind == .primary ? Color.white.opacity(0.4) : KTEditorTheme.separator
        }
    }

    struct DraftIconButton: View {
        let systemImage: String
        var tint: Color = KTEditorTheme.label2

        var body: some View {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 28, height: 26)
                .background(KTEditorTheme.btnBg.opacity(0.001), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    struct DraftChip: View {
        let text: String

        var body: some View {
            HStack(spacing: 6) {
                Text(text).font(.system(size: 11.5)).foregroundStyle(KTEditorTheme.label)
                Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(KTEditorTheme.label3)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(KTEditorTheme.pillBg, in: RoundedRectangle(cornerRadius: 6))
        }
    }

#endif
