import KTStackKit
import SwiftUI

struct DocumentListView: View {
    @EnvironmentObject private var vm: DocumentViewModel
    @State private var selectedID: String?
    @State private var editor: DocumentEditorView.Mode?
    @State private var pendingDelete: DocumentRecord?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            filterBar
            Divider()
            content
        }
        .sheet(item: $editor) { DocumentEditorView(mode: $0) }
        .alert("Delete this document?", isPresented: deleteConfirmBinding, presenting: pendingDelete) { record in
            Button("Delete", role: .destructive) { Task { _ = await vm.delete(record: record) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("This permanently removes the document from the collection.") }
        .alert("Operation failed", isPresented: editErrorBinding, presenting: vm.editError) { _ in
            Button("OK", role: .cancel) { vm.clearEditError() }
        } message: { Text($0) }
    }

    @ViewBuilder
    private var content: some View {
        if vm.selectedCollection == nil {
            EmptyStateView(
                symbol: "doc.text",
                title: "No collection selected",
                message: "Pick a collection on the left to browse its documents."
            )
        } else if let error = vm.resultError {
            EmptyStateView(
                symbol: "exclamationmark.triangle",
                title: "Couldn’t load documents",
                message: error
            )
        } else if vm.documents.isEmpty {
            EmptyStateView(
                symbol: "tray",
                title: "No documents",
                message: "This query returned no documents."
            )
        } else {
            List(vm.documents, selection: $selectedID) { record in
                card(record).tag(record.id)
            }
            .listStyle(.inset)
        }
    }

    private func card(_ record: DocumentRecord) -> some View {
        VStack(alignment: .leading, spacing: KDSpacing.space1) {
            Text("_id: \(record.id)").font(KDFont.footnote).foregroundStyle(.secondary)
            Text(record.json)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(12)
        }
        .padding(.vertical, KDSpacing.space1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !vm.isReadOnlyConnection { editor = .edit(record) } }
        .contextMenu {
            if !vm.isReadOnlyConnection {
                Button("Edit…") { editor = .edit(record) }
                Button("Delete", role: .destructive) { pendingDelete = record }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: KDSpacing.space2) {
            if let collection = vm.selectedCollection {
                Label(collection, systemImage: "doc.text")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
            }
            if vm.isReadOnlyConnection {
                Label("read-only", systemImage: "lock").font(KDFont.footnote).foregroundStyle(.tertiary)
            }
            Spacer()
            if !vm.isReadOnlyConnection {
                Button { editor = .insert } label: { Image(systemName: "plus") }
                    .help("Insert document").disabled(vm.selectedCollection == nil || vm.isBusy)
                Button { if let id = selectedID, let record = record(for: id) { editor = .edit(record) } }
                    label: { Image(systemName: "pencil") }
                    .help("Edit selected").disabled(selectedID == nil || vm.isBusy)
                Button { pendingDelete = selectedID.flatMap(record(for:)) } label: { Image(systemName: "trash") }
                    .help("Delete selected").disabled(selectedID == nil || vm.isBusy)
                Divider().frame(height: 16)
            }
            pager
        }
        .padding(KDSpacing.space2)
    }

    private var filterBar: some View {
        HStack(spacing: KDSpacing.space2) {
            Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
            TextField(#"Filter (JSON), e.g. {"name":"alice"}"#, text: $vm.filterText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.footnote, design: .monospaced))
                .onSubmit { Task { await vm.applyFilter() } }
            Button("Apply") { Task { await vm.applyFilter() } }
                .disabled(vm.selectedCollection == nil || vm.isBusy)
        }
        .padding(KDSpacing.space2)
    }

    private var pager: some View {
        HStack(spacing: KDSpacing.space2) {
            if !vm.documents.isEmpty {
                Text("docs \(vm.pageOffset + 1)–\(vm.pageOffset + vm.documents.count)")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
            }
            Button { Task { await vm.previousPage() } } label: { Image(systemName: "chevron.left") }
                .disabled(vm.pageOffset == 0 || vm.isBusy)
            Button { Task { await vm.nextPage() } } label: { Image(systemName: "chevron.right") }
                .disabled(!vm.hasMorePages || vm.isBusy)
        }
    }

    private func record(for id: String) -> DocumentRecord? {
        vm.documents.first { $0.id == id }
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var editErrorBinding: Binding<Bool> {
        Binding(get: { vm.editError != nil }, set: { if !$0 { vm.clearEditError() } })
    }
}
