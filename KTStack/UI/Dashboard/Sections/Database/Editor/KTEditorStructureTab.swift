import SwiftUI
import KTStackKit

struct KTEditorStructureTab: View {
    @EnvironmentObject private var vm: DatabaseViewModel

    private let columns = ["Column", "Type", "Null", "Key", "Default"]
    private let weights: [CGFloat] = [1.4, 1.2, 0.6, 0.7, 1.1]

    var body: some View {
        Group {
            if vm.selectedTable == nil {
                placeholder("Select a table to view its structure.")
            } else if vm.currentColumns.isEmpty {
                placeholder("No columns found for this table.")
            } else {
                GeometryReader { geo in
                    let widths = columnWidths(total: geo.size.width)
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section { rows(widths) } header: { headerRow(widths) }
                        }
                    }
                }
            }
        }
        .task(id: vm.selectedTable) { await vm.loadStructure() }
    }

    private func columnWidths(total: CGFloat) -> [CGFloat] {
        let sum = weights.reduce(0, +)
        return weights.map { $0 / sum * max(total, 560) }
    }

    private func headerRow(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, title in
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(KTColor.ink3)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .frame(width: widths[index], alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xF7F7FA))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xE6E6EC)).frame(height: 0.5) }
    }

    private func rows(_ widths: [CGFloat]) -> some View {
        ForEach(vm.currentColumns) { column in
            HStack(spacing: 0) {
                cell(column.name, width: widths[0], font: .system(size: 13, weight: .semibold, design: .monospaced), color: KTColor.ink)
                cell(column.dataType, width: widths[1], font: .system(size: 13, design: .monospaced), color: Color(hex: 0x8B5CF6))
                cell(column.isNullable ? "YES" : "NO", width: widths[2], font: .system(size: 13), color: KTColor.ink3)
                keyCell(column, width: widths[3])
                cell(column.defaultValue ?? "—", width: widths[4], font: .system(size: 13, design: .monospaced), color: KTColor.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sepFaint).frame(height: 0.5) }
        }
    }

    private func cell(_ text: String, width: CGFloat, font: Font, color: Color) -> some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func keyCell(_ column: ColumnInfo, width: CGFloat) -> some View {
        HStack {
            if column.isPrimaryKey {
                Text("PK")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(KTColor.accent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color(hex: 0xEAF1FF)))
            } else {
                Text("").frame(height: 1)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
    }

    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle").font(.system(size: 42, weight: .light)).foregroundStyle(KTColor.faint)
            Text(message).font(.system(size: 13)).foregroundStyle(KTColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
