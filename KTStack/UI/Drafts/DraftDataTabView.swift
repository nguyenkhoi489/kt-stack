#if DEBUG
    import KTStackKit
    import SwiftUI

    struct DraftDataTabView: View {
        private let table = DraftSampleData.tables[0]
        private let selectedRowIndex = 1

        var body: some View {
            DraftChrome(activeTab: .data) {
                VStack(spacing: 0) {
                    contentHeader
                    breadcrumb
                    filterBar
                    HStack(spacing: 0) {
                        DraftGrid(
                            columnTitles: columnTitles,
                            rows: table.rows,
                            selectedRowIndex: selectedRowIndex,
                            editingCell: (row: 2, column: 1)
                        )
                        rowDetail
                    }
                    footer
                }
            }
        }

        private var columnTitles: [String] {
            table.columns.map(\.name)
        }

        private var contentHeader: some View {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: 0xFFF1E0))
                    .frame(width: 22, height: 22)
                    .overlay(Image(systemName: "tablecells").font(.system(size: 11)).foregroundStyle(KTEditorTheme.switcherIcon))
                Text(table.name).font(.jbMono(14)).foregroundStyle(KTEditorTheme.label)
                Text("\(table.rowCount.formatted()) rows loaded")
                    .font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.label2)
                Spacer()
                DraftButton(title: "Export CSV")
                DraftIconButton(systemImage: "sidebar.right", tint: KTEditorTheme.accent)
                DraftIconButton(systemImage: "trash", tint: KTEditorTheme.Status.error)
                DraftButton(title: "Add Row", systemImage: "plus")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
        }

        private var breadcrumb: some View {
            HStack(spacing: 6) {
                Text("countries").font(.system(size: 12)).foregroundStyle(KTEditorTheme.accent)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(KTEditorTheme.faint)
                Text("users").font(.system(size: 12, weight: .medium)).foregroundStyle(KTEditorTheme.label)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(KTEditorTheme.accentSoft)
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
        }

        private var filterBar: some View {
            HStack(spacing: 8) {
                DraftButton(title: "Filter", systemImage: "line.3.horizontal.decrease")
                DraftChip(text: "balance > 100.00")
                DraftChip(text: "country_id = 12")
                Spacer()
                Text("Clear").font(.system(size: 12, weight: .medium)).foregroundStyle(KTEditorTheme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
        }

        private var rowDetail: some View {
            VStack(spacing: 0) {
                HStack {
                    Text("Row Detail").font(.jbMono(12.5, .bold)).foregroundStyle(KTEditorTheme.label)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(table.columns.enumerated()), id: \.element.id) { index, column in
                            detailField(column: column, cell: table.rows[selectedRowIndex].cells[index])
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 270)
            .background(KTEditorTheme.content2)
            .overlay(alignment: .leading) { Divider().overlay(KTEditorTheme.separator) }
        }

        private func detailField(column: DraftColumn, cell: DraftCell) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(column.name).font(.jbMono(11, .semibold)).foregroundStyle(KTEditorTheme.label2)
                detailValue(cell)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
        }

        @ViewBuilder
        private func detailValue(_ cell: DraftCell) -> some View {
            switch cell {
            case let .text(value): Text(value).font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.label)
            case let .number(value): Text(value).font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.label)
            case let .foreign(value): Text(value).font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.accent)
            case .null: Text("NULL").font(.jbMono(12.5)).italic().foregroundStyle(KTEditorTheme.faint)
            }
        }

        private var footer: some View {
            HStack(spacing: 8) {
                Text("\(table.rowCount.formatted()) rows loaded · scroll for more")
                    .font(.jbMono(12)).foregroundStyle(KTEditorTheme.label2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(KTEditorTheme.content2)
            .overlay(alignment: .top) { Divider().overlay(KTEditorTheme.separator) }
        }
    }

    #if DEBUG
        #Preview {
            DraftDataTabView().frame(width: 1200, height: 720)
        }
    #endif

#endif
