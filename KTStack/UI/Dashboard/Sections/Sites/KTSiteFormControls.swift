import AppKit
import KTStackKit
import SwiftUI

enum KTSiteFormControls {
    static func row(
        _ label: String,
        labelWidth: CGFloat = 138,
        topAligned: Bool = false,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: topAligned ? .top : .center, spacing: 16) {
            Text(label).font(.jbMono(14.5, .regular)).foregroundStyle(KTColor.ink)
                .frame(width: labelWidth, alignment: .leading)
                .padding(.top, topAligned ? 10 : 0)
            content()
            Spacer(minLength: 0)
        }
    }

    static func fieldBox(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(KTColor.fieldBorderStrong, lineWidth: 1.5))
    }

    static func formDropdown(
        width: CGFloat,
        options: [KTDropdownOption],
        @ViewBuilder leading: () -> some View,
        value: String
    ) -> some View {
        let lead = leading()
        return KTDropdown(width: width, options: options) {
            HStack(spacing: 11) {
                lead
                Text(value).font(.jbMono(14.5, .medium)).foregroundStyle(KTColor.ink)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(KTColor.muted)
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(KTColor.fieldBorderStrong, lineWidth: 1.5))
        }
    }

    static func smallTile(_ tint: KTTint, @ViewBuilder content: () -> some View) -> some View {
        content().foregroundStyle(tint.fg).frame(width: 27, height: 27)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.bg))
    }

    static var phpBadge: some View {
        Text("php").font(.jbMono(10, .bold)).foregroundStyle(.white)
            .padding(.vertical, 3).padding(.horizontal, 7)
            .background(Capsule().fill(Color(hex: 0x777BB3)))
    }

    static func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .regular)).foregroundStyle(KTColor.ink3)
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func helper(_ text: String) -> some View {
        Text(text).font(.jbMono(12.5)).foregroundStyle(KTColor.muted)
    }

    static func advancedToggle(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.jbMono(14, .regular)).foregroundStyle(KTColor.ink)
                Text(subtitle).font(.jbMono(12.5)).foregroundStyle(KTColor.muted)
            }
            Spacer()
            KTToggle(isOn: binding.wrappedValue) { binding.wrappedValue.toggle() }
        }
    }

    static var hairline: some View {
        Rectangle().fill(Color(hex: 0xF0F0F3)).frame(height: 0.5)
    }
}
