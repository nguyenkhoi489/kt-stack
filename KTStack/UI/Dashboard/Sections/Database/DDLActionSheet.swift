import KTStackKit
import SwiftUI

/// Form for composing CREATE TABLE / ADD COLUMN. It only builds `ColumnDefinition`s and asks the
/// view model to stage the DDL (`prepare…`); the actual SQL is shown for confirmation by the parent
/// structure view. Keeping composition in the VM means this view never touches the dialect directly.
struct DDLActionSheet: View {
    enum Mode: Identifiable {
        case createTable
        case addColumn
        var id: String {
            self == .createTable ? "create" : "add"
        }
    }

    @EnvironmentObject private var vm: DatabaseViewModel
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var tableName = ""
    @State private var rows: [DraftColumn] = [DraftColumn()]

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
            Text(title).font(KDFont.title).padding(KDSpacing.space3)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: KDSpacing.space3) {
                    if isCreate {
                        labeledField("Table name") {
                            TextField("table_name", text: $tableName)
                                .textFieldStyle(.roundedBorder).font(KDFont.mono)
                        }
                    }
                    ForEach($rows) { $row in columnEditor($row) }
                    if isCreate {
                        Button { rows.append(DraftColumn()) } label: {
                            Label("Add column", systemImage: "plus")
                        }.buttonStyle(.borderless)
                    }
                }
                .padding(KDSpacing.space3)
            }
            Divider()
            footer
        }
        .frame(width: 460, height: 480)
    }

    private func columnEditor(_ row: Binding<DraftColumn>) -> some View {
        VStack(alignment: .leading, spacing: KDSpacing.space1) {
            HStack(spacing: KDSpacing.space2) {
                TextField("name", text: row.name).textFieldStyle(.roundedBorder).font(KDFont.mono)
                TextField("type", text: row.type).textFieldStyle(.roundedBorder).font(KDFont.mono)
                    .frame(width: 150)
                if isCreate, rows.count > 1 {
                    Button { removeColumn(row.wrappedValue.id) } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.borderless)
                }
            }
            HStack(spacing: KDSpacing.space3) {
                Toggle("Nullable", isOn: row.nullable).toggleStyle(.checkbox).font(KDFont.footnote)
                Toggle("Primary key", isOn: row.primaryKey).toggleStyle(.checkbox).font(KDFont.footnote)
            }
        }
        .padding(KDSpacing.space2)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Compose SQL") { compose() }
                .keyboardShortcut(.defaultAction).disabled(!isValid)
        }
        .padding(KDSpacing.space3)
    }

    private var isValid: Bool {
        let named = rows.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard named else { return false }
        if isCreate { return !tableName.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private func removeColumn(_ id: UUID) {
        rows.removeAll { $0.id == id }
    }

    private func definitions() -> [ColumnDefinition] {
        rows.map {
            ColumnDefinition(
                name: $0.name.trimmingCharacters(in: .whitespaces),
                type: $0.type,
                isNullable: $0.nullable,
                isPrimaryKey: $0.primaryKey
            )
        }
    }

    private func compose() {
        switch mode {
        case .createTable:
            vm.prepareCreateTable(
                name: tableName.trimmingCharacters(in: .whitespaces),
                columns: definitions()
            )
        case .addColumn:
            if let first = definitions().first { vm.prepareAddColumn(first) }
        }
        dismiss() // the staged SQL (or a ddlError) surfaces in the parent structure view
    }

    private func labeledField(
        _ label: String,
        @ViewBuilder _ content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(KDFont.footnote).foregroundStyle(.secondary)
            content()
        }
    }
}
