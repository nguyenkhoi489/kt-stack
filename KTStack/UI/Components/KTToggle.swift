import SwiftUI
import KTStackKit

struct KTToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? KTColor.accent : Color(hex: 0xE3E3E9))
                    .frame(width: KTMetric.toggleWidth, height: KTMetric.toggleHeight)
                Circle()
                    .fill(.white)
                    .frame(width: KTMetric.toggleKnob, height: KTMetric.toggleKnob)
                    .shadow(color: .black.opacity(0.28), radius: 1, y: 1)
                    .padding(3)
            }
            .animation(.easeInOut(duration: 0.18), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
