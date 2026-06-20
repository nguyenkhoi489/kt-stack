import SwiftUI
import KTStackKit

struct KTEditorDataTab: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    @Binding var selectedRow: Int?
    @Binding var editor: TableDataView.EditorMode?
    @Binding var pendingDelete: Int?

    var body: some View {
        VStack(spacing: 0) {
            contentHeader
            Rectangle().fill(KTColor.sep).frame(height: 0.5)
            body(for: vm.selectedTable)
        }
        .onAppear(perform: reloadIfNeeded)
    }

    private func reloadIfNeeded() {
        guard let table = vm.selectedTable, !vm.isTableBrowse, !vm.isBusy else { return }
        Task { await vm.select(table: table) }
    }

    @ViewBuilder
    private func body(for table: TableInfo?) -> some View {
        if table == nil {
            emptyState
        } else if let result = vm.result, vm.isTableBrowse {
            KTDataGrid(result: result,
                       selectedRow: $selectedRow,
                       onActivate: { if vm.canEditRows { editor = .edit($0) } },
                       onNearEnd: { Task { await vm.loadMoreRows() } })
            footer(result)
        } else if let error = vm.resultError {
            messageState(icon: "exclamationmark.triangle", title: "Couldn’t load rows", message: error)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var contentHeader: some View {
        HStack(spacing: 10) {
            if let table = vm.selectedTable {
                Image(systemName: table.isView ? "eye" : "tablecells")
                    .font(.system(size: 14)).foregroundStyle(Color(hex: 0x86868F))
                Text(table.name)
                    .font(.jbMono(14, .regular))
                    .foregroundStyle(KTColor.ink)
                if let result = vm.result, vm.isTableBrowse {
                    Text("· \(rowCountLabel(result))")
                        .font(.jbMono(12.5)).foregroundStyle(KTColor.muted)
                }
                Spacer()
                if vm.canEditRows {
                    rowActions
                }
            } else {
                Text("Select a table to begin").font(.jbMono(13)).foregroundStyle(KTColor.muted)
                Spacer()
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .frame(minHeight: 48)
    }

    private var rowActions: some View {
        HStack(spacing: 8) {
            if selectedRow != nil {
                iconButton("trash", tint: KTColor.danger) { pendingDelete = selectedRow }
            }
            Button { editor = .insert } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text("Add Row").font(.jbMono(12.5, .medium))
                }
                .foregroundStyle(KTColor.ink2)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(KTColor.btnBorder, lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(vm.isBusy)
        }
    }

    private func iconButton(_ symbol: String, tint: Color = Color(hex: 0x86868F),
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowCountLabel(_ result: QueryResult) -> String {
        "\(result.rowCount) row\(result.rowCount == 1 ? "" : "s") loaded"
    }

    private func footer(_ result: QueryResult) -> some View {
        HStack(spacing: 8) {
            Text("\(result.rowCount) rows loaded\(vm.hasMorePages ? " · scroll for more" : "")")
                .font(.jbMono(12)).foregroundStyle(KTColor.muted)
            if vm.isFetchingMore {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(KTColor.sep).frame(height: 0.5) }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "tablecells")
                .font(.system(size: 60, weight: .ultraLight)).foregroundStyle(KTColor.faint)
            Text("No table selected")
                .font(.jbMono(20, .bold)).foregroundStyle(Color(hex: 0x86868F))
                .padding(.top, 20)
            Text("Pick a table in the schema tree to browse its rows.")
                .font(.jbMono(14)).foregroundStyle(Color(hex: 0xA8A8B0))
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 42, weight: .light)).foregroundStyle(KTColor.faint)
            Text(title).font(.jbMono(16, .regular)).foregroundStyle(KTColor.ink3)
            Text(message).font(.jbMono(13)).foregroundStyle(KTColor.muted).multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
