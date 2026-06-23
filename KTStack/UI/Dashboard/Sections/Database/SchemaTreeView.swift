import SwiftUI
import KTStackKit


struct SchemaTreeView: View {
    @EnvironmentObject private var vm: DatabaseViewModel

    var onSelectDatabase: () -> Void = {}
    var onOpenBackups: () -> Void = {}
    var onCreateDatabase: () -> Void = {}
    var onImportExport: () -> Void = {}
    var onlySelectedDatabase = false
    var canOpenBackups = false
    var canCreateDatabase = false
    var canImportExport = false
    var backupsHelp = "Open backups"
    var createDatabaseHelp = "Create Database"
    var importExportHelp = "Import / Export"
    var importExportSystemImage = "square.and.arrow.up.on.square"

    @State private var ddlSheet: DDLActionSheet.Mode?
    @State private var sidebarDDLActive = false
    @State private var confirmDropDb: DatabaseInfo?
    @State private var dropDatabaseSheet: DatabaseInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: KDSpacing.space2) {
                Text("Schema")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
                if vm.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
                SchemaHeaderButton(systemImage: "externaldrive.badge.timemachine",
                                   help: backupsHelp,
                                   isEnabled: canOpenBackups,
                                   action: onOpenBackups)
                SchemaHeaderButton(systemImage: "plus",
                                   help: createDatabaseHelp,
                                   isEnabled: canCreateDatabase,
                                   action: onCreateDatabase)
                SchemaHeaderButton(systemImage: importExportSystemImage,
                                   help: importExportHelp,
                                   isEnabled: canImportExport,
                                   action: onImportExport)
            }
            .padding(.horizontal, KDSpacing.space3)
            .padding(.vertical, KDSpacing.space2)
            .zIndex(2)
            Divider()
            content
        }
        .frame(minWidth: 180, idealWidth: 220)
        .sheet(item: $ddlSheet) { DDLActionSheet(mode: $0) }
        .sheet(item: $dropDatabaseSheet, onDismiss: finishDropDatabaseSheet) { db in
            DropDatabaseConfirmationSheet(database: db)
                .environmentObject(vm)
        }
        .alert("Run this SQL?",
               isPresented: .init(get: { vm.pendingDDL != nil && sidebarDDLActive && confirmDropDb == nil },
                                  set: { if !$0 { cancelSidebarDDL() } }),
               presenting: vm.pendingDDL) { _ in
            Button("Run", role: .destructive) { confirmSidebarDDL() }
            Button("Cancel", role: .cancel) { cancelSidebarDDL() }
        } message: { Text($0) }
        .alert("DDL error",
               isPresented: .init(get: { vm.ddlError != nil && sidebarDDLActive },
                                  set: { if !$0 { vm.clearDDLError(); sidebarDDLActive = false } }),
               presenting: vm.ddlError) { _ in
            Button("OK", role: .cancel) { vm.clearDDLError(); sidebarDDLActive = false }
        } message: { Text($0) }
    }

    @ViewBuilder
    private var content: some View {
        if vm.connection == .connected {
            if onlySelectedDatabase {
                selectedDatabaseList
            } else {
                List {
                    ForEach(vm.databases) { db in databaseRow(db) }
                }
                .listStyle(.sidebar)
            }
        } else {
            VStack {
                Spacer()
                Text("Pick a connection to browse its schema.")
                    .font(KDFont.footnote).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).padding(KDSpacing.space3)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var selectedDatabaseList: some View {
        if let database = vm.selectedDatabase {
            if vm.isBusy && vm.tables.isEmpty {
                VStack(spacing: KDSpacing.space2) {
                    Spacer()
                    ProgressView()
                    Text("Loading tables…")
                        .font(KDFont.footnote).foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    Section(database) {
                        ForEach(vm.tables) { table in tableRow(table) }
                    }
                }
                .listStyle(.sidebar)
            }
        } else {
            VStack {
                Spacer()
                Text("Pick a database to browse its tables.")
                    .font(KDFont.footnote).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).padding(KDSpacing.space3)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func databaseRow(_ db: DatabaseInfo) -> some View {
        let isSelected = vm.selectedDatabase == db.name
        HStack(spacing: KDSpacing.space2) {
            Image(systemName: "cylinder")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Text(db.name).font(KDFont.body)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if vm.selectedDatabase != db.name { vm.selectDatabaseDeferred(db.name) }
            onSelectDatabase()
        }
        .contextMenu {
            if vm.selectedDatabase != db.name {
                Button("Select") {
                    vm.selectDatabaseDeferred(db.name)
                    onSelectDatabase()
                }
                Divider()
            }
            Button("Drop Database…", role: .destructive) {
                confirmDropDb = db
                vm.prepareDropDatabase(db.name)
                if vm.pendingDDL != nil { dropDatabaseSheet = db }
            }
            .disabled(vm.isReadOnlyConnection || !vm.canDropDatabase)
        }
    }

    @ViewBuilder
    private func tableRow(_ table: TableInfo) -> some View {
        let isSelected = vm.selectedTable?.id == table.id
        HStack(spacing: KDSpacing.space2) {
            Image(systemName: table.isView ? "eye" : "tablecells")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Text(table.name).font(KDFont.body)
            if table.isView {
                Text("view").font(KDFont.footnote).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                await vm.select(table: table)
                onSelectDatabase()
            }
        }
        .contextMenu {
            if !table.isView && !vm.isReadOnlyConnection {
                Button("Add Column…") {
                    Task {
                        await vm.select(table: table)
                        sidebarDDLActive = true
                        ddlSheet = .addColumn
                    }
                }
                Divider()
                Button("Drop Table…", role: .destructive) {
                    Task {
                        await vm.select(table: table)
                        sidebarDDLActive = true
                        vm.prepareDropTable()
                    }
                }
            }
        }
    }

    private func confirmSidebarDDL() {
        sidebarDDLActive = false
        if let db = confirmDropDb {
            let name = db.name
            confirmDropDb = nil
            Task { await vm.confirmDropDatabase(name) }
        } else {
            Task { await vm.confirmDDL() }
        }
    }

    private func cancelSidebarDDL() {
        vm.cancelDDL()
        sidebarDDLActive = false
        confirmDropDb = nil
    }

    private func finishDropDatabaseSheet() {
        vm.cancelDDL()
        sidebarDDLActive = false
        confirmDropDb = nil
    }
}

struct SchemaHeaderButton: View {
    let systemImage: String
    let help: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            if isEnabled { action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .opacity(isEnabled ? 1 : 0.38)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .zIndex(hovering ? 900 : 0)
        .overlay(alignment: .bottom) {
            if hovering {
                Text(help)
                    .font(.jbMono(11))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .fixedSize()
                    .offset(y: 26)
                    .allowsHitTesting(false)
                    .zIndex(200)
            }
        }
    }
}
