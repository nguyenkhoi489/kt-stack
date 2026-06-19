import SwiftUI
import AppKit
import KTStackKit

struct KTEditorResultGrid: View {
    let result: QueryResult
    var selectedRow: Int?
    var onSelect: ((Int) -> Void)?
    var onActivate: ((Int) -> Void)?

    private var baseWidths: [CGFloat] {
        result.columns.enumerated().map { index, column in
            var longest = column.name.count
            for row in result.rows.prefix(80) {
                if let text = row[safe: index]?.displayText { longest = max(longest, text.count) }
            }
            return min(max(CGFloat(longest) * 7.6 + 28, 110), 360)
        }
    }

    private func resolvedWidths(available: CGFloat) -> [CGFloat] {
        let base = baseWidths
        let total = base.reduce(0, +)
        guard total > 0, available > total else { return base }
        let scale = available / total
        return base.map { $0 * scale }
    }

    var body: some View {
        GeometryReader { geo in
            let widths = resolvedWidths(available: geo.size.width)
            let contentWidth = widths.reduce(0, +)
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section { rows(widths) } header: { headerRow(widths) }
                }
                .frame(width: contentWidth, alignment: .leading)
            }
            .background(KTColor.contentBg)
        }
    }

    private func headerRow(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(result.columns.enumerated()), id: \.offset) { index, column in
                Text(column.name)
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(KTColor.ink3)
                    .lineLimit(1)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .frame(width: widths[index], alignment: .leading)
                    .overlay(alignment: .trailing) { Rectangle().fill(KTColor.sepFaint).frame(width: 0.5) }
            }
        }
        .background(Color(hex: 0xF7F7FA))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xE6E6EC)).frame(height: 0.5) }
    }

    private func rows(_ widths: [CGFloat]) -> some View {
        ForEach(Array(result.rows.enumerated()), id: \.offset) { rowIndex, cells in
            HStack(spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.offset) { columnIndex, cell in
                    cellView(cell)
                        .frame(width: widths[safe: columnIndex] ?? 140, alignment: .leading)
                }
            }
            .background(selectedRow == rowIndex ? KTColor.accentSoft : Color.clear)
            .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sepFaint).frame(height: 0.5) }
            .contentShape(Rectangle())
            .onTapGesture { onSelect?(rowIndex) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { onActivate?(rowIndex) })
            .contextMenu {
                Button("Copy Row") { copyRow(cells) }
                if onActivate != nil { Button("Edit Row…") { onActivate?(rowIndex) } }
            }
        }
    }

    private func copyRow(_ cells: [Cell]) {
        let line = cells.map { $0.displayText ?? "NULL" }.joined(separator: "\t")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
    }

    @ViewBuilder
    private func cellView(_ cell: Cell) -> some View {
        if let text = cell.displayText {
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(KTColor.ink2)
                .lineLimit(1)
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 8)
        } else {
            Text("NULL")
                .font(.system(size: 12.5, design: .monospaced).italic())
                .foregroundStyle(KTColor.faint)
                .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
