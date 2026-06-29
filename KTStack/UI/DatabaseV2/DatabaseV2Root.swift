import KTStackKit
import SwiftUI

enum V2EditorTab: String, CaseIterable, Identifiable {
    case data = "Data"
    case structure = "Structure"
    case query = "Query"
    case er = "ER"

    var id: String {
        rawValue
    }

    var symbol: String {
        switch self {
        case .data: "tablecells"
        case .structure: "list.bullet.rectangle"
        case .query: "terminal"
        case .er: "point.3.connected.trianglepath.dotted"
        }
    }
}

struct V2ConnectionPill: View {
    let state: DatabaseV2ViewModel.ConnectionState

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(pillColor).frame(width: 7, height: 7)
            Text(pillLabel)
                .font(.system(size: 11))
                .foregroundStyle(KTEditorTheme.label2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(KTEditorTheme.pillBg, in: Capsule())
    }

    private var pillColor: Color {
        switch state {
        case .connected: KTEditorTheme.Status.running
        case .connecting: KTEditorTheme.accent
        case .idle: KTEditorTheme.Status.error
        case .failed: KTEditorTheme.Status.error
        }
    }

    private var pillLabel: String {
        switch state {
        case .idle: "Idle"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .failed: "Failed"
        }
    }
}

struct V2TableSidebar: View {
    let schemaName: String
    let databases: [DatabaseInfo]
    let tables: [TableInfo]
    let selectedTable: TableInfo?
    let onSelectDatabase: (String) -> Void
    let onSelect: (TableInfo) -> Void

    @State private var filterText = ""

    private var filteredTables: [TableInfo] {
        guard !filterText.isEmpty else { return tables }
        return tables.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            databaseSwitcher
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }

            HStack(spacing: 8) {
                Text("TABLES")
                    .font(.jbMono(11, .bold))
                    .tracking(0.5)
                    .foregroundStyle(KTEditorTheme.label2)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            filterField
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(filteredTables) { table in
                        tableRow(table)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 248)
        .background(KTEditorTheme.sidebar)
        .overlay(alignment: .trailing) { Divider().overlay(KTEditorTheme.separator) }
    }

    private var databaseSwitcher: some View {
        HStack(spacing: 7) {
            Image(systemName: "cylinder.split.1x2")
                .foregroundStyle(KTEditorTheme.switcherIcon)
            Text(schemaName.isEmpty ? "—" : schemaName)
                .font(.jbMono(12.5, .semibold))
                .foregroundStyle(KTEditorTheme.label)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10))
                .foregroundStyle(KTEditorTheme.label3)
        }
        .contentShape(Rectangle())
        .overlay {
            Menu {
                ForEach(databases, id: \.name) { db in
                    Button {
                        onSelectDatabase(db.name)
                    } label: {
                        if db.name == schemaName {
                            Label(db.name, systemImage: "checkmark")
                        } else {
                            Text(db.name)
                        }
                    }
                }
            } label: {
                Rectangle().fill(Color.clear).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(databases.isEmpty)
        }
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(KTEditorTheme.label3)
            ZStack(alignment: .leading) {
                if filterText.isEmpty {
                    Text("Filter tables")
                        .font(.system(size: 12.5))
                        .foregroundStyle(KTEditorTheme.label3)
                        .allowsHitTesting(false)
                }
                TextField("", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(KTEditorTheme.label)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(KTEditorTheme.fieldBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(KTEditorTheme.fieldBorder, lineWidth: 1))
    }

    private func tableRow(_ table: TableInfo) -> some View {
        let isSelected = table.name == selectedTable?.name
        return HStack(spacing: 8) {
            Image(systemName: table.isView ? "eye" : "tablecells")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : KTEditorTheme.label3)
                .frame(width: 14)
            Text(table.name)
                .font(.jbMono(12.5))
                .foregroundStyle(isSelected ? .white : KTEditorTheme.label)
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            isSelected ? KTEditorTheme.accent : .clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect(table) }
    }
}

struct DatabaseV2Root: View {
    @ObservedObject var vm: DatabaseV2ViewModel
    let onClose: () -> Void

    @State private var activeTab: V2EditorTab = .data
    @State private var showInsertSheet = false
    @State private var pendingDeleteRow: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            objectTabs
            HStack(spacing: 0) {
                V2TableSidebar(
                    schemaName: vm.schemaName,
                    databases: vm.databases,
                    tables: vm.tables,
                    selectedTable: vm.selectedTable,
                    onSelectDatabase: { name in Task { await vm.select(database: name) } },
                    onSelect: { vm.select(table: $0) }
                )
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(KTEditorTheme.content)
            }
            .task(id: activeTab) {
                guard activeTab == .er, !vm.diagramLoaded else { return }
                await vm.loadDiagram()
            }
        }
        .background(KTEditorTheme.window)
        .sheet(isPresented: $showInsertSheet) {
            V2RowEditorSheet(vm: vm)
        }
        .alert(
            "Delete this row?",
            isPresented: Binding(
                get: { pendingDeleteRow != nil },
                set: { if !$0 { pendingDeleteRow = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingDeleteRow = nil }
            Button("Delete", role: .destructive) {
                if let row = pendingDeleteRow {
                    Task { await vm.deleteRow(row) }
                    pendingDeleteRow = nil
                }
            }
        } message: {
            Text("This permanently removes 1 row from \(vm.selectedTable?.name ?? "the table"). This action cannot be undone.")
        }
    }

    private var titlebar: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: 0xFFF1E0))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "cylinder.split.1x2")
                        .font(.system(size: 12))
                        .foregroundStyle(KTEditorTheme.switcherIcon)
                )
            HStack(spacing: 6) {
                Text("SQL Editor")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KTEditorTheme.label)
                Text(vm.schemaName.isEmpty ? "—" : vm.schemaName)
                    .font(.jbMono(12))
                    .foregroundStyle(KTEditorTheme.label2)
            }
            Spacer()
            V2ConnectionPill(state: vm.connectionState)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .frame(height: 44)
        .background(
            LinearGradient(
                colors: [KTEditorTheme.titlebarTop, KTEditorTheme.titlebarBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
    }

    private var objectTabs: some View {
        HStack(spacing: 2) {
            ForEach(V2EditorTab.allCases) { tab in
                let isActive = tab == activeTab
                HStack(spacing: 6) {
                    Image(systemName: tab.symbol).font(.system(size: 11)).opacity(0.8)
                    Text(tab.rawValue).font(.system(size: 12))
                }
                .foregroundStyle(isActive ? KTEditorTheme.label : KTEditorTheme.label2)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isActive ? KTEditorTheme.content : .clear,
                    in: UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                )
                .overlay(alignment: .bottom) {
                    if isActive { Rectangle().fill(KTEditorTheme.accent).frame(height: 1.5) }
                }
                .contentShape(Rectangle())
                .onTapGesture { activeTab = tab }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(KTEditorTheme.window)
        .overlay(alignment: .bottom) { Divider().overlay(KTEditorTheme.separator) }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .data:
            V2DataTabView(vm: vm, showInsertSheet: $showInsertSheet, pendingDeleteRow: $pendingDeleteRow)
        case .structure:
            V2StructureTabView(vm: vm)
        case .query:
            V2QueryTabView(vm: vm)
        case .er:
            V2ERTabView(vm: vm)
        }
    }
}
