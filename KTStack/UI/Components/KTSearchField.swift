import KTStackKit
import SwiftUI

struct KTSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search…"

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(KTColor.muted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.jbMono(14))
                .foregroundStyle(KTColor.ink)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KTColor.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: KTRadius.field, style: .continuous).fill(KTColor.fieldBg))
        .overlay(RoundedRectangle(cornerRadius: KTRadius.field, style: .continuous).strokeBorder(KTColor.fieldBorder, lineWidth: 0.5))
    }
}
