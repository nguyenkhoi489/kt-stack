#if DEBUG
    import KTStackKit
    import SwiftUI

    struct DraftGrid: View {
        let columnTitles: [String]
        let rows: [DraftRow]
        var selectedRowIndex: Int?
        var editingCell: (row: Int, column: Int)?

        private let rownumWidth: CGFloat = 44

        var body: some View {
            ScrollView([.vertical]) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section(header: header) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            gridRow(index: index, row: row)
                        }
                    }
                }
            }
            .background(KTEditorTheme.content)
        }

        private var header: some View {
            HStack(spacing: 0) {
                headerCell("#", width: rownumWidth, alignment: .trailing)
                ForEach(columnTitles, id: \.self) { title in
                    headerCell(title, width: nil, alignment: .leading)
                }
            }
            .background(KTEditorTheme.Grid.headerBg)
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.Grid.border) }
        }

        @ViewBuilder
        private func headerCell(_ title: String, width: CGFloat?, alignment: Alignment) -> some View {
            let label = Text(title)
                .font(.jbMono(11, .semibold))
                .foregroundStyle(KTEditorTheme.label2)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            Group {
                if let width {
                    label.frame(width: width, alignment: alignment)
                } else {
                    label.frame(maxWidth: .infinity, alignment: alignment)
                }
            }
            .overlay(alignment: .trailing) { Rectangle().fill(KTEditorTheme.Grid.border).frame(width: 1) }
        }

        private func gridRow(index: Int, row: DraftRow) -> some View {
            let isSelected = index == selectedRowIndex
            return HStack(spacing: 0) {
                Text("\(index + 1)")
                    .font(.jbMono(12))
                    .foregroundStyle(KTEditorTheme.label3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(width: rownumWidth, alignment: .trailing)
                    .background(KTEditorTheme.Grid.rownumBg)
                    .overlay(alignment: .trailing) { Rectangle().fill(KTEditorTheme.Grid.border).frame(width: 1) }
                ForEach(Array(row.cells.enumerated()), id: \.offset) { columnIndex, cell in
                    cellView(cell, isEditing: editingCell?.row == index && editingCell?.column == columnIndex)
                }
            }
            .background(isSelected ? KTEditorTheme.accentSoft : KTEditorTheme.content)
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.Grid.border) }
        }

        @ViewBuilder
        private func cellView(_ cell: DraftCell, isEditing: Bool) -> some View {
            let alignment: Alignment = {
                if case .number = cell { return .trailing }
                return .leading
            }()
            cellText(cell)
                .font(.jbMono(12))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: alignment)
                .background(isEditing ? KTEditorTheme.Grid.editBg : .clear)
                .overlay {
                    if isEditing {
                        RoundedRectangle(cornerRadius: 2).stroke(KTEditorTheme.Grid.editOutline, lineWidth: 2)
                    }
                }
                .overlay(alignment: .trailing) { Rectangle().fill(KTEditorTheme.Grid.border).frame(width: 1) }
        }

        @ViewBuilder
        private func cellText(_ cell: DraftCell) -> some View {
            switch cell {
            case let .text(value):
                Text(value).foregroundStyle(KTEditorTheme.Grid.cellText)
            case let .number(value):
                Text(value).foregroundStyle(KTEditorTheme.Grid.number)
            case let .foreign(value):
                Text(value).foregroundStyle(KTEditorTheme.accent)
            case .null:
                Text("NULL").italic().foregroundStyle(KTEditorTheme.Grid.nullText)
            }
        }
    }

#endif
