import KTStackKit
import SwiftUI

struct KTDropdownOption: Identifiable {
    let id = UUID()
    let label: String
    let active: Bool
    let action: () -> Void
}

struct KTDropdown<Label: View>: View {
    var width: CGFloat = 170
    var maxHeight: CGFloat?
    var compact: Bool = false
    let options: [KTDropdownOption]
    @ViewBuilder var label: () -> Label

    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                menu.frame(width: width)
            }
    }

    @ViewBuilder
    private var menu: some View {
        let stack = VStack(alignment: .leading, spacing: 1) {
            ForEach(options) { option in
                KTDropdownRow(option: option, compact: compact) { open = false }
            }
        }
        .padding(6)

        if let maxHeight {
            ScrollView { stack }.frame(maxHeight: maxHeight)
        } else {
            stack
        }
    }
}

private struct KTDropdownRow: View {
    let option: KTDropdownOption
    var compact: Bool = false
    let dismiss: () -> Void

    @State private var hovering = false

    var body: some View {
        Button { option.action(); dismiss() } label: {
            HStack(spacing: compact ? 6 : 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: compact ? 9 : 11, weight: .bold))
                    .foregroundStyle(KTColor.accent)
                    .opacity(option.active ? 1 : 0)
                    .frame(width: compact ? 11 : 14)
                Text(option.label).font(.jbMono(compact ? 11 : 13)).foregroundStyle(KTColor.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 8 : 10).padding(.vertical, compact ? 4 : 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? KTColor.accentSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct KTDropdownChevronLabel: View {
    let text: String
    var mono = false

    var body: some View {
        HStack(spacing: 7) {
            Text(text)
                .font(.jbMono(13, mono ? .regular : .medium))
                .foregroundStyle(mono ? KTColor.ink2 : KTColor.ink)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .regular)).foregroundStyle(KTColor.muted)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KTColor.fieldBg))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(KTColor.fieldBorder, lineWidth: 0.5))
    }
}
