import SwiftUI
import KDWarmKit


struct SchemaTreeView: View {
    @EnvironmentObject private var vm: DatabaseViewModel

    var onSelectDatabase: () -> Void = {}
    var onCreateDatabase: () -> Void = {}
    var onlySelectedDatabase = false
    var canCreateDatabase = false
    var createDatabaseHelp = "Create Database..."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: KDSpacing.space2) {
                Text("Schema")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(action: onCreateDatabase) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(createDatabaseHelp)
                .disabled(!canCreateDatabase)
            }
            .padding(.horizontal, KDSpacing.space3)
            .padding(.vertical, KDSpacing.space2)
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
