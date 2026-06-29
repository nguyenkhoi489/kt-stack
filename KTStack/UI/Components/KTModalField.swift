import KTStackKit
import SwiftUI

struct KTModalField: View {
    let placeholder: String
    @Binding var text: String
    var mono = false
    var isSecure = false

    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.jbMono(14))
        .foregroundStyle(KTColor.ink)
        .focused($focused)
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(focused ? KTColor.accent : Color(hex: 0xE2E2E8), lineWidth: 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(KTColor.accentSoft, lineWidth: focused ? 3 : 0)
                .blur(radius: 1)
        )
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

struct KTModalLabeledRow<Content: View>: View {
    let label: String
    var labelWidth: CGFloat = 130
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.jbMono(13.5, .regular))
                .foregroundStyle(KTColor.ink)
                .frame(width: labelWidth, alignment: .leading)
            content()
        }
    }
}
