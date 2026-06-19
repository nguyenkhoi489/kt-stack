import SwiftUI
import KTStackKit

struct KTSegmentedTabs<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }
    }

    let items: [Item]
    @Binding var selection: Value
    var large = false

    private var fontSize: CGFloat { large ? 14 : 13 }
    private var vPad: CGFloat { large ? 8 : 5 }
    private var hPad: CGFloat { large ? 18 : 13 }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let active = item.value == selection
                Button { selection = item.value } label: {
                    Text(item.label)
                        .font(.system(size: fontSize, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? KTColor.ink : KTColor.ink3)
                        .padding(.vertical, vPad)
                        .padding(.horizontal, hPad)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(active ? Color.white : Color.clear)
                                .shadow(color: active ? .black.opacity(0.10) : .clear, radius: 1.5, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: KTRadius.segment, style: .continuous).fill(KTColor.segmentBg))
    }
}
