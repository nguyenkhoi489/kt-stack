import SwiftUI
import KTStackKit

struct KTEditorDataTab: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    @Binding var selectedRow: Int?
    @Binding var editor: RowEditorMode?
    @Binding var pendingDelete: Int?
    let isActive: Bool

    @State private var showFilterPopover = false
    @State private var showDetailPanel = false

    var body: some View {
        VStack(spacing: 0) {
            contentHeader
            Rectangle().fill(KTColor.sep).frame(height: 0.5)
            if !vm.navigationStack.isEmpty {
                KTBreadcrumbBar(trail: breadcrumbTrail, onBack: { Task { await vm.popNavigation(); selectedRow = nil } })
                Rectangle().fill(KTColor.sep).frame(height: 0.5)
            }
            if vm.isTableBrowse {
                filterBar
                Rectangle().fill(KTColor.sep).frame(height: 0.5)
            }
            body(for: vm.selectedTable)
        }
        .onAppear { if isActive { reloadIfNeeded() } }
        .task(id: EditorTabTaskKey(value: vm.selectedTable?.name, isActive: isActive)) {
            guard isActive else { return }
            await vm.loadRelationsIfNeeded()
        }
    }

    private var breadcrumbTrail: [String] {
        vm.navigationStack.map(\.table.name) + [vm.selectedTable?.name ?? ""]
    }

    private var foreignKeyColumnNames: Set<String> {
        guard let table = vm.selectedTable else { return [] }
        return Set(vm.navigableForeignKeys(forTable: table.name).keys)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Button { showFilterPopover = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10.5, weight: .semibold))
                    Text("Filter").font(.jbMono(12, .medium))
                }
                .foregroundStyle(KTColor.ink2)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(KTColor.btnBorder, lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
                KTColumnFilterPopover(
                    columns: vm.currentColumns.map(\.name),
                    onAdd: { condition in Task { await vm.applyFilters(vm.activeFilters + [condition]) } },
                    onClose: { showFilterPopover = false })
            }

            ForEach(Array(vm.activeFilters.enumerated()), id: \.offset) { index, condition in
                filterChip(condition, at: index)
            }

            if !vm.activeFilters.isEmpty || vm.activeSort != nil {
                Button("Clear") { Task { await vm.clearFiltersAndSort(); selectedRow = nil } }
                    .buttonStyle(.plain)
                    .font(.jbMono(12, .medium))
                    .foregroundStyle(KTColor.accent)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func filterChip(_ condition: FilterCondition, at index: Int) -> some View {
        HStack(spacing: 5) {
            Text(chipLabel(condition)).font(.jbMono(11.5)).foregroundStyle(KTColor.ink2).lineLimit(1)
            Button {
                var next = vm.activeFilters
                next.remove(at: index)
                Task { await vm.applyFilters(next) }
            } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(KTColor.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(KTColor.pillBg))
    }

    private func chipLabel(_ c: FilterCondition) -> String {
        switch c.op {
        case .isNull:    return "\(c.column) is null"
        case .isNotNull: return "\(c.column) is not null"
        case .equals:      return "\(c.column) = \(c.value.displayText ?? "")"
        case .notEquals:   return "\(c.column) ≠ \(c.value.displayText ?? "")"
        case .contains:    return "\(c.column) ⊃ \(c.value.displayText ?? "")"
        case .greaterThan: return "\(c.column) > \(c.value.displayText ?? "")"
        case .lessThan:    return "\(c.column) < \(c.value.displayText ?? "")"
        }
    }

    private func reloadIfNeeded() {
        guard let table = vm.selectedTable, !vm.isTableBrowse, !vm.isBusy,
              vm.navigationStack.isEmpty else { return }
        Task { await vm.select(table: table) }
    }

    @ViewBuilder
    private func body(for table: TableInfo?) -> some View {
        if table == nil {
            emptyState
        } else if let result = vm.result, vm.isTableBrowse {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    KTDataGrid(result: result,
                               selectedRow: $selectedRow,
                               onActivate: { if vm.canEditRows { editor = .edit($0) } },
                               onNearEnd: { Task { await vm.loadMoreRows() } },
                               sort: vm.activeSort,
                               onSortColumn: { column in Task { await vm.toggleSort(column: column) } },
                               editableColumns: editableColumnNames(result),
                               onCommitEdit: { row, column, value in
                                   guard column >= 0, column < result.columns.count else { return }
                                   let name = result.columns[column].name
                                   Task { await vm.updateCell(rowIndex: row, column: name, stringValue: value) }
                               },
                               foreignKeyColumns: foreignKeyColumnNames,
                               onNavigateFK: { row, column in
                                   guard row < result.rows.count, column >= 0, column < result.columns.count else { return }
                                   let name = result.columns[column].name
                                   let value = result.rows[row][column]
                                   Task { await vm.navigateForeignKey(fromColumn: name, value: value) }
                               })
                    footer(result)
                }
                if showDetailPanel {
                    Rectangle().fill(KTColor.sep).frame(width: 0.5)
                    KTRowDetailPanel(
                        columns: result.columns,
                        row: selectedRow.flatMap { $0 < result.rows.count ? result.rows[$0] : nil },
                        onClose: { showDetailPanel = false })
                }
            }
        } else if let error = vm.resultError {
            messageState(icon: "exclamationmark.triangle", title: "Couldn’t load rows", message: error)
        } else {
            VStack(spacing: 10) {
                ProgressView()
                if let label = vm.currentActivityLabel {
                    Text(label).font(.jbMono(12.5)).foregroundStyle(KTColor.muted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                if vm.isTableBrowse, !vm.canEditRows, let reason = vm.editDisabledReason {
                    Text(reason).font(.jbMono(11.5)).foregroundStyle(KTColor.muted).lineLimit(1)
                }
                if vm.isTableBrowse {
                    CSVExportButton(defaultName: table.name)
                }
                detailToggle
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

    private var detailToggle: some View {
        Button { showDetailPanel.toggle() } label: {
            Image(systemName: "sidebar.trailing")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(showDetailPanel ? KTColor.accent : Color(hex: 0x86868F))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func editableColumnNames(_ result: QueryResult) -> Set<String> {
        guard vm.canEditRows else { return [] }
        let primaryKeys = Set(vm.primaryKeyColumns.map(\.name))
        return Set(result.columns.map(\.name)).subtracting(primaryKeys)
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
