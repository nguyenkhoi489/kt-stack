#if DEBUG
    import KTStackKit
    import SwiftUI

    struct DraftStructureTabView: View {
        private let table = DraftSampleData.tables[0]
        private let selectedColumnIndex = 0

        var body: some View {
            DraftChrome(activeTab: .structure) {
                VStack(spacing: 0) {
                    ddlToolbar
                    columnsTable
                    indexesSection
                    Spacer(minLength: 0)
                }
            }
        }

        private var ddlToolbar: some View {
            HStack(spacing: 8) {
                DraftButton(title: "New Table", systemImage: "plus")
                DraftButton(title: "Add Column", systemImage: "plus.rectangle")
                DraftButton(title: "Drop Column", kind: .danger)
                DraftButton(title: "Drop Table", kind: .danger)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
        }

        private var columnsTable: some View {
            VStack(spacing: 0) {
                columnHeader
                ForEach(Array(table.columns.enumerated()), id: \.element.id) { index, column in
                    columnRow(column, isSelected: index == selectedColumnIndex)
                }
            }
        }

        private var columnHeader: some View {
            HStack(spacing: 0) {
                headerCell("name", flex: 2)
                headerCell("type", flex: 2)
                headerCell("nullable", flex: 1)
                headerCell("key", flex: 1)
                headerCell("default", flex: 2)
            }
            .background(KTEditorTheme.Grid.headerBg)
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
        }

        private func headerCell(_ title: String, flex: CGFloat) -> some View {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(KTEditorTheme.label2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(flex)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
        }

        private func columnRow(_ column: DraftColumn, isSelected: Bool) -> some View {
            HStack(spacing: 0) {
                Text(column.name).font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.label)
                    .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(2).padding(.horizontal, 16)
                Text(column.type).font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.Syntax.type)
                    .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(2).padding(.horizontal, 16)
                Text(column.nullable ? "YES" : "NO").font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.label2)
                    .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1).padding(.horizontal, 16)
                keyCell(column.key)
                    .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1).padding(.horizontal, 16)
                Text(column.defaultValue ?? "—").font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.label2)
                    .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(2).padding(.horizontal, 16)
            }
            .padding(.vertical, 9)
            .background(isSelected ? KTEditorTheme.accentSoft : .clear)
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
        }

        @ViewBuilder
        private func keyCell(_ key: DraftColumnKey) -> some View {
            switch key {
            case .primary:
                Text("PK")
                    .font(.jbMono(11, .bold))
                    .foregroundStyle(KTEditorTheme.accent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(KTEditorTheme.accentSoft, in: RoundedRectangle(cornerRadius: 5))
            case .foreign:
                Text("FK").font(.jbMono(11, .bold)).foregroundStyle(KTEditorTheme.accent)
            case .none:
                Text("").frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private var indexesSection: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("INDEXES")
                    .font(.jbMono(12.5, .bold))
                    .foregroundStyle(KTEditorTheme.label2)
                    .padding(.bottom, 8)
                ForEach(DraftSampleData.indexes, id: \.name) { index in
                    HStack(spacing: 8) {
                        Image(systemName: index.unique ? "key.fill" : "number")
                            .font(.system(size: 11)).foregroundStyle(KTEditorTheme.label2)
                        Text(index.name).font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.label)
                        Text("(\(index.columns))").font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.label2)
                        if index.unique {
                            Text("UNIQUE").font(.jbMono(11)).foregroundStyle(KTEditorTheme.accent)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    #if DEBUG
        #Preview {
            DraftStructureTabView().frame(width: 1200, height: 720)
        }
    #endif

#endif
