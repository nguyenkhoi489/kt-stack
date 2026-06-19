import SwiftUI
import KTStackKit

struct KTSettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold)).tracking(0.5)
                .foregroundStyle(KTColor.muted)
                .padding(.bottom, 9)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(KTColor.sep, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .padding(.bottom, 22)
    }
}

struct KTSettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var showDivider = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(KTColor.ink)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(KTColor.muted)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if showDivider { Rectangle().fill(KTColor.sepFaint).frame(height: 0.5) }
        }
    }
}

struct KTSettingsMenuValue: View {
    let text: String
    var mono = false

    var body: some View {
        HStack(spacing: 7) {
            Text(text)
                .font(.system(size: 13, weight: mono ? .semibold : .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(mono ? KTColor.ink2 : KTColor.ink)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(KTColor.muted)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KTColor.fieldBg))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(KTColor.fieldBorder, lineWidth: 0.5))
    }
}

struct KTSettingsValuePill: View {
    let text: String
    var mono = true

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: mono ? .monospaced : .default))
            .foregroundStyle(KTColor.ink2)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KTColor.fieldBg))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(KTColor.fieldBorder, lineWidth: 0.5))
    }
}

struct KTSettingsTextButton: View {
    let title: String
    var danger = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .medium))
                .foregroundStyle(danger ? KTColor.danger : KTColor.ink)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? (danger ? KTColor.dangerBg : KTColor.btnHover) : Color.white))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(danger ? KTColor.dangerBorder : KTColor.btnBorder, lineWidth: 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
