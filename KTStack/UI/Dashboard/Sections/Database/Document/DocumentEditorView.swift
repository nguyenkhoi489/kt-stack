import KTStackKit
import SwiftUI

struct DocumentEditorView: View {
    @EnvironmentObject private var vm: DocumentViewModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: Identifiable {
        case insert
        case edit(DocumentRecord)
        var id: String {
            if case let .edit(record) = self { return "edit-\(record.id)" }
            return "insert"
        }
    }

    let mode: Mode

    @State private var json = "{\n  \n}"
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Text(isEditing ? "Edit Document" : "Insert Document").font(KDFont.headline)
            editor
            if let validationError {
                Label(validationError, systemImage: "exclamationmark.triangle.fill")
                    .font(KDFont.footnote).foregroundStyle(.orange).lineLimit(3)
            }
            Divider()
            footer
        }
        .padding(KDSpacing.space4)
        .frame(width: 520, height: 460)
        .onAppear(perform: hydrate)
    }

    private var editor: some View {
        TextEditor(text: $json)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            .onChange(of: json) { _ in validationError = nil }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(isEditing ? "Save" : "Insert", action: save)
                .keyboardShortcut(.defaultAction)
                .disabled(vm.isBusy)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func hydrate() {
        if case let .edit(record) = mode { json = record.json }
    }

    private func save() {
        if let reason = DocumentViewModel.validateJSON(json) {
            validationError = reason
            return
        }
        Task {
            let succeeded: Bool = switch mode {
            case .insert:
                await vm.insert(json: json)
            case let .edit(record):
                await vm.update(record: record, json: json)
            }
            if succeeded { dismiss() } else { validationError = vm.editError }
        }
    }
}
