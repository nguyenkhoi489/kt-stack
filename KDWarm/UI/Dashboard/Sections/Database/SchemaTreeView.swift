import SwiftUI
import KDWarmKit


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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: KDSpacing.space2) {
                Text("Schema")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
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
                    .font(.system(size: 11))
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
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                    .allowsHitTesting(false)
                    .zIndex(200)
            }
        }
    }
}
