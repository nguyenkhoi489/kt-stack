import KTStackKit
import SwiftUI

struct V2DataTabView: View {
    @ObservedObject var vm: DatabaseV2ViewModel
    @Binding var showInsertSheet: Bool
    @Binding var pendingDeleteRow: Int?

    @State private var selectedRowIndex: Int? = nil
    @State private var showRowDetail = false

    var body: some View {
        VStack(spacing: 0) {
            contentHeader
            if let errorMessage = vm.editError {
                editErrorBanner(errorMessage)
            }
            if vm.isLoadingRows, vm.rows == nil {
                loadingPlaceholder
            } else if let result = vm.rows {
                HStack(spacing: 0) {
                    KTDataGrid(
                        result: result,
                        selectedRow: $selectedRowIndex,
                        onActivate: nil,
                        onNearEnd: { Task { await vm.fetchMore() } },
                        editableColumns: vm.canEdit ? vm.editableColumns : [],
                        onCommitEdit: { row, column, value in
                            Task { await vm.updateCell(row: row, column: column, newValue: value) }
                        },
                        foreignKeyColumns: foreignKeyColumnNames,
                        onNavigateFK: nil
                    )
                    if showRowDetail, let idx = selectedRowIndex, idx < result.rows.count {
                        rowDetailPanel(columns: result.columns, row: result.rows[idx])
                    }
                }
                footer(rowCount: result.rowCount)
            } else if let errorMessage = vm.loadError {
                errorPlaceholder(errorMessage)
            } else {
                emptyPlaceholder
            }
        }
    }

    private var foreignKeyColumnNames: Set<String> {
        guard let table = vm.selectedTable else { return [] }
        return Set(vm.foreignKeys.filter { $0.fromTable == table.name }.map(\.fromColumn))
    }

    private var contentHeader: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: 0xFFF1E0))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "tablecells")
                        .font(.system(size: 11))
                        .foregroundStyle(KTEditorTheme.switcherIcon)
                )
            Text(vm.selectedTable?.name ?? "—")
                .font(.jbMono(14))
                .foregroundStyle(KTEditorTheme.label)
            if let result = vm.rows {
                Text("\(result.rowCount) rows loaded")
                    .font(.jbMono(12.5))
                    .foregroundStyle(KTEditorTheme.label2)
            }
            if vm.selectedTable != nil, !vm.canEdit {
                Text("No primary key — edit disabled")
                    .font(.jbMono(11))
                    .foregroundStyle(KTEditorTheme.label3)
            }
            Spacer()
            V2IconButton(systemImage: "plus") {
                showInsertSheet = true
            }
            .disabled(vm.selectedTable == nil)
            V2IconButton(
                systemImage: "trash",
                tint: selectedRowIndex != nil && vm.canEdit
                    ? KTEditorTheme.Status.error
                    : KTEditorTheme.label3
            ) {
                pendingDeleteRow = selectedRowIndex
            }
            .disabled(!vm.canEdit || selectedRowIndex == nil)
            V2IconButton(
                systemImage: "sidebar.right",
                tint: showRowDetail ? KTEditorTheme.accent : KTEditorTheme.label2,
                action: { showRowDetail.toggle() }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
    }

    private func editErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(KTEditorTheme.Status.error)
            Text(message)
                .font(.jbMono(12))
                .foregroundStyle(KTEditorTheme.Status.error)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(KTEditorTheme.Status.error.opacity(0.08))
        .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
    }

    private var loadingPlaceholder: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(KTEditorTheme.content)
    }

    private var emptyPlaceholder: some View {
        VStack {
            Spacer()
            Text(vm.selectedTable == nil ? "Select a table" : "No data")
                .font(.jbMono(13))
                .foregroundStyle(KTEditorTheme.label3)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(KTEditorTheme.content)
    }

    private func errorPlaceholder(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.jbMono(12))
                .foregroundStyle(KTEditorTheme.Status.error)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(KTEditorTheme.content)
    }

    private func rowDetailPanel(columns: [ColumnMeta], row: [Cell]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Row Detail")
                    .font(.jbMono(12.5, .bold))
                    .foregroundStyle(KTEditorTheme.label)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, col in
                        detailField(
                            columnName: col.name,
                            cell: index < row.count ? row[index] : .null
                        )
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 270)
        .background(KTEditorTheme.content2)
        .overlay(alignment: .leading) { Divider().overlay(KTEditorTheme.separator) }
    }

    private func detailField(columnName: String, cell: Cell) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(columnName)
                .font(.jbMono(11, .semibold))
                .foregroundStyle(KTEditorTheme.label2)
            detailCellValue(cell)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
    }

    @ViewBuilder
    private func detailCellValue(_ cell: Cell) -> some View {
        switch cell {
        case .null:
            Text("NULL").font(.jbMono(12.5)).italic().foregroundStyle(KTEditorTheme.faint)
        case let .int(n):
            Text(String(n)).font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.Grid.number)
        case let .double(d):
            Text(String(d)).font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.Grid.number)
        case let .bool(b):
            Text(b ? "true" : "false").font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.label)
        case let .text(s):
            Text(s).font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.label)
        case let .blob(d):
            Text("[\(d.count) bytes]").font(.jbMono(12.5)).italic().foregroundStyle(KTEditorTheme.faint)
        }
    }

    private func footer(rowCount: Int) -> some View {
        HStack(spacing: 8) {
            if vm.isLoadingRows {
                ProgressView().scaleEffect(0.7)
            }
            Text(footerText(rowCount: rowCount))
                .font(.jbMono(12))
                .foregroundStyle(KTEditorTheme.label2)
            Spacer()
            if vm.hasMore, !vm.isLoadingRows {
                V2Button(title: "Load more") {
                    Task { await vm.fetchMore() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(KTEditorTheme.content2)
        .overlay(alignment: .top) { Divider().overlay(KTEditorTheme.separator) }
    }

    private func footerText(rowCount: Int) -> String {
        var text = "\(rowCount) rows loaded"
        if vm.hasMore { text += " · scroll for more" }
        return text
    }
}
