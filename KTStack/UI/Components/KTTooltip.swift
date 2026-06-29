import KTStackKit
import SwiftUI

private struct KTTooltipPayload {
    let text: String
    let anchor: Anchor<CGRect>
}

private struct KTTooltipKey: PreferenceKey {
    static var defaultValue: KTTooltipPayload?
    static func reduce(value: inout KTTooltipPayload?, nextValue: () -> KTTooltipPayload?) {
        if let next = nextValue() { value = next }
    }
}

private struct KTTooltipModifier: ViewModifier {
    let text: String
    let delay: Double

    @State private var hovering = false
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                if inside {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if hovering { visible = true }
                    }
                } else {
                    visible = false
                }
            }
            .anchorPreference(key: KTTooltipKey.self, value: .bounds) { anchor in
                visible ? KTTooltipPayload(text: text, anchor: anchor) : nil
            }
    }
}

private struct KTTooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.jbMono(11))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.9)))
    }
}

extension View {
    func ktTip(_ text: String, delay: Double = 0.35) -> some View {
        modifier(KTTooltipModifier(text: text, delay: delay))
    }

    func ktTooltipHost() -> some View {
        overlayPreferenceValue(KTTooltipKey.self) { payload in
            GeometryReader { proxy in
                if let payload {
                    let rect = proxy[payload.anchor]
                    KTTooltipBubble(text: payload.text)
                        .position(x: rect.midX, y: rect.minY)
                        .offset(y: -17)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.1), value: payload?.text)
        }
    }
}
