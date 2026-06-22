import SwiftUI
import KTStackKit

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
            .overlay(alignment: .top) {
                if visible {
                    bubble
                        .alignmentGuide(.top) { $0[.bottom] }
                        .offset(y: -6)
                        .transition(.opacity)
                        .zIndex(1000)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.12), value: visible)
    }

    private var bubble: some View {
        Text(text)
            .font(.jbMono(11))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.88)))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }
}

extension View {
    func ktTip(_ text: String, delay: Double = 0.35) -> some View {
        modifier(KTTooltipModifier(text: text, delay: delay))
    }
}
