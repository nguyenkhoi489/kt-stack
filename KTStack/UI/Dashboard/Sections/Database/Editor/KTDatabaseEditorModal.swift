import SwiftUI
import KTStackKit

struct KTDatabaseEditorModal: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    let onClose: () -> Void

    enum EditorTab: Hashable { case data, structure, query, er }

    @State private var tab: EditorTab = .data
    @State private var tableFilter = ""
    @State private var selectedRow: Int?
    @State private var rowEditor: TableDataView.EditorMode?
    @State private var pendingDelete: Int?
    @State private var ddlSheet: DDLActionSheet.Mode?

    private var engineTint: KTTint {
        KTEngineTint.of(vm.selectedProfile?.kind.rawValue ?? "mysql")
    }

    private var schemaName: String {
        vm.selectedDatabase ?? vm.selectedProfile?.name ?? "database"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                KTColor.modalScrim.ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                card
                    .frame(width: min(1200, geo.size.width - 56),
                           height: min(760, geo.size.height - 56))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            headerBar
            HStack(spacing: 0) {
                KTEditorTableSidebar(filter: $tableFilter,
                                     onRefresh: { Task { await reloadCurrentDatabase() } },
                                     onAddTable: { ddlSheet = .createTable })
                tabContent
            }
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 36, y: 18)
        .background(escCatcher)
        .onChange(of: vm.selectedTable) { _ in selectedRow = nil; pendingDelete = nil }
        .sheet(item: $rowEditor) { RowEditorView(mode: $0) }
        .sheet(item: $ddlSheet) { DDLActionSheet(mode: $0) }
        .alert("Delete this row?", isPresented: deleteBinding, presenting: pendingDelete) { row in
            Button("Delete", role: .destructive) { Task { await vm.deleteRow(at: row); selectedRow = nil } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("This permanently removes the row from the table.") }
        .alert("Edit failed", isPresented: editErrorBinding, presenting: vm.editError) { _ in
            Button("OK", role: .cancel) { vm.clearEditError() }
        } message: { Text($0) }
        .alert("Run this SQL?", isPresented: ddlConfirmBinding, presenting: vm.pendingDDL) { _ in
            Button("Run", role: .destructive) { Task { await vm.confirmDDL() } }
            Button("Cancel", role: .cancel) { vm.cancelDDL() }
        } message: { Text($0) }
        .alert("DDL error", isPresented: ddlErrorBinding, presenting: vm.ddlError) { _ in
            Button("OK", role: .cancel) { vm.clearDDLError() }
        } message: { Text($0) }
    }

    private var headerBar: some View {
        HStack(spacing: 13) {
            KTIconTile(tint: engineTint, size: 30, radius: 8) {
                Image(systemName: "cylinder.split.1x2").font(.system(size: 15, weight: .medium))
            }
            Text(schemaName)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(KTColor.ink)
            connectionBadge
            Spacer()
            KTSegmentedTabs(items: [.init(value: EditorTab.data, label: "Data"),
                                    .init(value: .structure, label: "Structure"),
                                    .init(value: .query, label: "Query"),
                                    .init(value: .er, label: "ER")],
                            selection: $tab)
            closeButton
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .background(LinearGradient(colors: [Color(hex: 0xFBFBFD), .white], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sep).frame(height: 0.5) }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        switch vm.connection {
        case .connected:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.system(size: 13, weight: .semibold))
                Text("Connected").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(KTColor.online)
        case .connecting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Connecting…").font(.system(size: 13)).foregroundStyle(KTColor.muted)
            }
        default:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 13))
                Text("Disconnected").font(.system(size: 13))
            }
            .foregroundStyle(KTColor.danger)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
                .foregroundStyle(KTColor.muted).frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch tab {
            case .data:      KTEditorDataTab(selectedRow: $selectedRow, editor: $rowEditor, pendingDelete: $pendingDelete)
            case .structure: KTEditorStructureTab()
            case .query:     KTEditorQueryTab()
            case .er:        KTEditorERTab()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reloadCurrentDatabase() async {
        guard let database = vm.selectedDatabase else { return }
        await vm.select(database: database)
    }

    private var escCatcher: some View {
        Button(action: onClose) { Color.clear }
            .keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
    private var editErrorBinding: Binding<Bool> {
        Binding(get: { vm.editError != nil }, set: { if !$0 { vm.clearEditError() } })
    }
    private var ddlConfirmBinding: Binding<Bool> {
        Binding(get: { vm.pendingDDL != nil }, set: { if !$0 { vm.cancelDDL() } })
    }
    private var ddlErrorBinding: Binding<Bool> {
        Binding(get: { vm.ddlError != nil }, set: { if !$0 { vm.clearDDLError() } })
    }
}
