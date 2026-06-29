import KTStackKit
import SwiftUI

struct V2StructureTabView: View {
    @ObservedObject var vm: DatabaseV2ViewModel

    @State private var ddlSheetMode: V2DDLSheet.Mode = .createTable
    @State private var showDDLSheet = false
    @State private var selectedColumnName: String?
    @State private var pendingDropTableSQL: String?
    @State private var pendingDropColumnSQL: String?

    private enum ColumnKeyKind { case primary, foreign, none }

    var body: some View {
        VStack(spacing: 0) {
            ddlToolbar
            if let error = vm.ddlError {
                ddlErrorBanner(error)
            }
            if vm.selectedTable == nil {
                centeredLabel("Select a table")
            } else if !vm.columns.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        columnHeader
                        ForEach(vm.columns) { column in
                            columnRow(column)
                        }
                        if !vm.indexes.isEmpty {
                            indexesSection
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else if let errorMessage = vm.loadError {
                centeredError(errorMessage)
            } else if vm.isLoadingStructure {
                centeredLabel("Loading…")
            } else {
                centeredLabel("No columns")
            }
        }
        .onChange(of: vm.selectedTable) { _ in
            selectedColumnName = nil
        }
        .sheet(isPresented: $showDDLSheet) {
            V2DDLSheet(vm: vm, mode: ddlSheetMode)
        }
        .alert(
            "Drop Table?",
            isPresented: Binding(
                get: { pendingDropTableSQL != nil },
                set: { if !$0 { pendingDropTableSQL = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingDropTableSQL = nil }
            Button("Drop", role: .destructive) {
                if let sql = pendingDropTableSQL {
                    Task { await vm.runDDL(sql) }
                    pendingDropTableSQL = nil
                }
            }
        } message: {
            Text(pendingDropTableSQL ?? "")
        }
        .alert(
            "Drop Column?",
            isPresented: Binding(
                get: { pendingDropColumnSQL != nil },
                set: { if !$0 { pendingDropColumnSQL = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingDropColumnSQL = nil }
            Button("Drop", role: .destructive) {
                if let sql = pendingDropColumnSQL {
                    Task { await vm.runDDL(sql) }
                    pendingDropColumnSQL = nil
                }
            }
        } message: {
            Text(pendingDropColumnSQL ?? "")
        }
    }

    private var ddlToolbar: some View {
        HStack(spacing: 8) {
            V2Button(title: "New Table", systemImage: "plus") {
                ddlSheetMode = .createTable
                showDDLSheet = true
            }
            V2Button(title: "Add Column", systemImage: "plus.rectangle") {
                guard vm.selectedTable != nil else { return }
                ddlSheetMode = .addColumn
                showDDLSheet = true
            }
            V2Button(title: "Drop Column", kind: .danger) {
                guard let column = selectedColumnName else { return }
                let sql = vm.composeDropColumn(column)
                guard !sql.isEmpty else { return }
                pendingDropColumnSQL = sql
            }
            V2Button(title: "Drop Table", kind: .danger) {
                guard vm.selectedTable != nil else { return }
                let sql = vm.composeDropTable()
                guard !sql.isEmpty else { return }
                pendingDropTableSQL = sql
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
    }

    private func ddlErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(KTEditorTheme.Status.error)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(KTEditorTheme.Status.error)
                .lineLimit(2)
            Spacer()
            Button {
                vm.clearDDLError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(KTEditorTheme.label3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(KTEditorTheme.Status.error.opacity(0.08))
        .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            headerCell("name", priority: 2)
            headerCell("type", priority: 2)
            headerCell("nullable", priority: 1)
            headerCell("key", priority: 1)
            headerCell("default", priority: 2)
        }
        .background(KTEditorTheme.Grid.headerBg)
        .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
    }

    private func headerCell(_ title: String, priority: Double) -> some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(KTEditorTheme.label2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(priority)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
    }

    private func columnRow(_ column: ColumnInfo) -> some View {
        let isSelected = column.name == selectedColumnName
        return HStack(spacing: 0) {
            Text(column.name)
                .font(.jbMono(12.5))
                .foregroundStyle(isSelected ? .white : KTEditorTheme.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(2)
                .padding(.horizontal, 16)
            Text(column.dataType)
                .font(.jbMono(12.5))
                .foregroundStyle(isSelected ? .white.opacity(0.85) : KTEditorTheme.Syntax.type)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(2)
                .padding(.horizontal, 16)
            Text(column.isNullable ? "YES" : "NO")
                .font(.jbMono(12.5))
                .foregroundStyle(isSelected ? .white.opacity(0.7) : KTEditorTheme.label2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .padding(.horizontal, 16)
            keyBadge(columnKey(for: column), selected: isSelected)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .padding(.horizontal, 16)
            Text(column.defaultValue ?? "—")
                .font(.jbMono(12.5))
                .foregroundStyle(isSelected ? .white.opacity(0.7) : KTEditorTheme.label2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(2)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 9)
        .background(isSelected ? KTEditorTheme.accent : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedColumnName = isSelected ? nil : column.name
        }
        .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
    }

    @ViewBuilder
    private func keyBadge(_ key: ColumnKeyKind, selected: Bool) -> some View {
        switch key {
        case .primary:
            Text("PK")
                .font(.jbMono(11, .bold))
                .foregroundStyle(selected ? .white : KTEditorTheme.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    selected ? Color.white.opacity(0.25) : KTEditorTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 5)
                )
        case .foreign:
            Text("FK")
                .font(.jbMono(11, .bold))
                .foregroundStyle(selected ? .white.opacity(0.85) : KTEditorTheme.accent)
        case .none:
            Text("")
        }
    }

    private var indexesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("INDEXES")
                .font(.jbMono(12.5, .bold))
                .foregroundStyle(KTEditorTheme.label2)
                .padding(.bottom, 8)
            ForEach(vm.indexes) { index in
                HStack(spacing: 8) {
                    Image(systemName: index.isUnique ? "key.fill" : "number")
                        .font(.system(size: 11))
                        .foregroundStyle(KTEditorTheme.label2)
                    Text(index.name)
                        .font(.jbMono(12.5))
                        .foregroundStyle(KTEditorTheme.label)
                    Text("(\(index.columns.joined(separator: ", ")))")
                        .font(.jbMono(12.5))
                        .foregroundStyle(KTEditorTheme.label2)
                    if index.isUnique {
                        Text("UNIQUE")
                            .font(.jbMono(11))
                            .foregroundStyle(KTEditorTheme.accent)
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

    private func columnKey(for column: ColumnInfo) -> ColumnKeyKind {
        if column.isPrimaryKey { return .primary }
        let tableName = vm.selectedTable?.name ?? ""
        let isForeignKey = vm.foreignKeys.contains {
            $0.fromTable == tableName && $0.fromColumn == column.name
        }
        return isForeignKey ? .foreign : .none
    }

    private func centeredLabel(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.jbMono(13)).foregroundStyle(KTEditorTheme.label3)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(KTEditorTheme.content)
    }

    private func centeredError(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.jbMono(12))
                .foregroundStyle(KTEditorTheme.Status.error)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(KTEditorTheme.content)
    }
}
