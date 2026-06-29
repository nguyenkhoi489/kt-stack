import KTStackKit
import SwiftUI

struct DumpTreeView: View {
    let node: DumpNode
    let depth: Int

    init(_ node: DumpNode, depth: Int = 0) {
        self.node = node
        self.depth = depth
    }

    var body: some View {
        switch node {
        case let .scalar(s):
            Text(s)
                .font(KDFont.mono)
                .foregroundStyle(scalarColor(s))
                .textSelection(.enabled)

        case let .array(items):
            if items.isEmpty {
                Text("[]").font(KDFont.mono).foregroundStyle(.secondary)
            } else {
                DisclosureGroup {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, pair in
                        HStack(alignment: .top, spacing: KDSpacing.space2) {
                            Text(pair.key)
                                .font(KDFont.mono)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 40, alignment: .trailing)
                            DumpTreeView(pair.value, depth: depth + 1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, KDSpacing.space3)
                    }
                } label: {
                    Text(node.displaySummary).font(KDFont.mono).foregroundStyle(.primary)
                }
            }

        case let .object(cls, props):
            if props.isEmpty {
                Text("\(cls) {}").font(KDFont.mono).foregroundStyle(.secondary)
            } else {
                DisclosureGroup {
                    ForEach(Array(props.enumerated()), id: \.offset) { _, pair in
                        HStack(alignment: .top, spacing: KDSpacing.space2) {
                            Text(pair.key)
                                .font(KDFont.mono)
                                .foregroundStyle(Color.KDStatus.info)
                                .frame(minWidth: 60, alignment: .trailing)
                            DumpTreeView(pair.value, depth: depth + 1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, KDSpacing.space3)
                    }
                } label: {
                    Text(cls).font(KDFont.mono).foregroundStyle(Color.KDStatus.info)
                }
            }

        case let .reference(n):
            Text("&\(n)").font(KDFont.mono).foregroundStyle(.secondary)
        }
    }

    private func scalarColor(_ value: String) -> Color {
        if value == "null" { return .secondary }
        if value == "true" || value == "false" { return Color.KDStatus.warning }
        if value.hasPrefix("\"") { return Color.KDStatus.running }
        return .primary
    }
}
