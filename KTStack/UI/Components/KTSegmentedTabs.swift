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

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let active = item.value == selection
                Button { selection = item.value } label: {
                    Text(item.label)
                        .font(.system(size: 13, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? KTColor.ink : KTColor.ink3)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(active ? Color.white : Color.clear)
                                .shadow(color: active ? .black.opacity(0.10) : .clear, radius: 1.5, y: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: KTRadius.segment, style: .continuous).fill(KTColor.segmentBg))
    }
}
