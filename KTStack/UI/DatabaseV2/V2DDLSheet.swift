import KTStackKit
import SwiftUI

struct V2DDLSheet: View {
    enum Mode: Identifiable {
        case createTable
        case addColumn
        var id: String {
            self == .createTable ? "create" : "add"
        }
    }

    @ObservedObject var vm: DatabaseV2ViewModel
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var tableName = ""
    @State private var columnDrafts: [DraftColumn] = [DraftColumn()]

    private struct DraftColumn: Identifiable {
        let id = UUID()
        var name = ""
        var type = "VARCHAR(255)"
        var nullable = true
        var primaryKey = false
    }

    private var isCreate: Bool {
        mode == .createTable
    }

    private var title: String {
        isCreate ? "New Table" : "Add Column"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KTEditorTheme.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            Divider().overlay(KTEditorTheme.separator)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isCreate {
                        tableNameField
                    }
                    ForEach($columnDrafts) { $draft in
                        columnDraftRow($draft)
                    }
                    if isCreate {
                        Button {
                            columnDrafts.append(DraftColumn())
                        } label: {
                            Label("Add column", systemImage: "plus")
                                .font(.system(size: 12.5))
                                .foregroundStyle(KTEditorTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            Divider().overlay(KTEditorTheme.separator)
            footer
        }
        .frame(width: isCreate ? 520 : 460, height: isCreate ? 480 : 260)
        .background(KTEditorTheme.content)
    }

    private var tableNameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Table name")
                .font(.system(size: 12.5))
                .foregroundStyle(KTEditorTheme.label)
            TextField("table_name", text: $tableName)
                .textFieldStyle(.roundedBorder)
                .font(.jbMono(12.5))
        }
    }

    private func columnDraftRow(_ draft: Binding<DraftColumn>) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("name", text: draft.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.jbMono(12.5))
                TextField("type", text: draft.type)
                    .textFieldStyle(.roundedBorder)
                    .font(.jbMono(12.5))
                    .frame(width: 150)
                if isCreate, columnDrafts.count > 1 {
                    Button {
                        columnDrafts.removeAll { $0.id == draft.wrappedValue.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(KTEditorTheme.Status.error)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 14) {
                Toggle("Nullable", isOn: draft.nullable)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                Toggle("Primary key", isOn: draft.primaryKey)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                Spacer()
            }
        }
        .padding(10)
        .background(KTEditorTheme.content2, in: RoundedRectangle(cornerRadius: 6))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Compose SQL") { compose() }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var isValid: Bool {
        let allFilled = columnDrafts.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty &&
                !$0.type.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard allFilled else { return false }
        if isCreate { return !tableName.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private func makeColumnDefinitions() -> [ColumnDefinition] {
        columnDrafts.map {
            ColumnDefinition(
                name: $0.name.trimmingCharacters(in: .whitespaces),
                type: $0.type.trimmingCharacters(in: .whitespaces),
                isNullable: $0.nullable,
                isPrimaryKey: $0.primaryKey
            )
        }
    }

    private func compose() {
        let sql: String
        switch mode {
        case .createTable:
            sql = vm.composeCreateTable(
                name: tableName.trimmingCharacters(in: .whitespaces),
                columns: makeColumnDefinitions()
            )
        case .addColumn:
            guard let first = makeColumnDefinitions().first else { return }
            sql = vm.composeAddColumn(first)
        }
        guard !sql.isEmpty else { return }
        dismiss()
        Task { await vm.runDDL(sql) }
    }
}
