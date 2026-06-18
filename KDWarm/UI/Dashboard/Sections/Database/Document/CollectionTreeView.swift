import SwiftUI
import KDWarmKit

struct CollectionTreeView: View {
    @EnvironmentObject private var vm: DocumentViewModel

    var onSelectDatabase: () -> Void = {}
    var onCreateDatabase: () -> Void = {}
    var canCreateDatabase = false
    var createDatabaseHelp = "Create Database..."

    @State private var expanded: Set<String> = []
    @State private var pendingDrop: String?
    @State private var creatingInDatabase: String?
    @State private var newCollectionName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: KDSpacing.space2) {
                Text("Collections")
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
        .alert("Drop this collection?", isPresented: dropConfirmBinding, presenting: pendingDrop) { name in
            Button("Drop", role: .destructive) { Task { _ = await vm.dropCollection(name) } }
            Button("Cancel", role: .cancel) {}
        } message: { name in Text("This permanently removes “\(name)” and all its documents.") }
        .alert("New Collection", isPresented: createBinding) {
            TextField("Collection name", text: $newCollectionName)
            Button("Create") { Task { _ = await vm.createCollection(name: newCollectionName) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.connection == .connected {
            List {
                ForEach(vm.databases) { database in databaseRow(database) }
            }
            .listStyle(.sidebar)
        } else {
            VStack {
                Spacer()
                Text("Pick a connection to browse its collections.")
                    .font(KDFont.footnote).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).padding(KDSpacing.space3)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func databaseRow(_ database: DatabaseInfo) -> some View {
        DisclosureGroup(isExpanded: expandedBinding(database.name)) {
            if vm.selectedDatabase == database.name {
                ForEach(vm.collections) { collection in collectionRow(collection) }
            }
        } label: {
            Label(database.name, systemImage: "cylinder").font(KDFont.body)
        }
        .contextMenu {
            if !vm.isReadOnlyConnection {
                Button("New Collection…") {
                    newCollectionName = ""
                    if vm.selectedDatabase != database.name { Task { await vm.select(database: database.name) } }
                    creatingInDatabase = database.name
                }
            }
        }
    }

    @ViewBuilder
    private func collectionRow(_ collection: CollectionInfo) -> some View {
        let isSelected = vm.selectedCollection == collection.name
        HStack(spacing: KDSpacing.space2) {
            Image(systemName: "doc.text")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Text(collection.name).font(KDFont.body)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await vm.select(collection: collection.name) }
            onSelectDatabase()
        }
        .contextMenu {
            if !vm.isReadOnlyConnection {
                Button("Drop Collection…", role: .destructive) { pendingDrop = collection.name }
            }
        }
    }

    private var dropConfirmBinding: Binding<Bool> {
        Binding(get: { pendingDrop != nil }, set: { if !$0 { pendingDrop = nil } })
    }

    private var createBinding: Binding<Bool> {
        Binding(get: { creatingInDatabase != nil }, set: { if !$0 { creatingInDatabase = nil } })
    }

    private func expandedBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(name) },
            set: { isOpen in
                if isOpen {
                    expanded.insert(name)
                    if vm.selectedDatabase != name { Task { await vm.select(database: name) } }
                    onSelectDatabase()
                } else {
                    expanded.remove(name)
                }
            })
    }
}
