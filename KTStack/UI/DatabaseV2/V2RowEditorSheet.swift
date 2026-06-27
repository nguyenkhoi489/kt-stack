import SwiftUI
import KTStackKit

struct V2RowEditorSheet: View {
    @ObservedObject var vm: DatabaseV2ViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var fields: [String: FieldState] = [:]

    private struct FieldState {
        var text: String
        var isNull: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Row")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KTEditorTheme.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if vm.columns.isEmpty {
                        Text("No column info available.")
                            .font(.jbMono(12.5))
                            .foregroundStyle(KTEditorTheme.label3)
                    } else {
                        ForEach(vm.columns) { column in
                            columnField(column)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }

            HStack(spacing: 10) {
                Spacer()
                V2Button(title: "Cancel") { dismiss() }
                V2Button(title: "Insert", kind: .primary) { commit() }
                    .disabled(vm.columns.isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Divider().overlay(KTEditorTheme.separator) }
        }
        .frame(width: 440)
        .background(KTEditorTheme.content)
        .onAppear { initFields() }
    }

    private func columnField(_ column: ColumnInfo) -> some View {
        let binding = fieldBinding(column.name)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(column.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(KTEditorTheme.label)
                if column.isPrimaryKey {
                    Text("PK")
                        .font(.system(size: 11))
                        .foregroundStyle(KTEditorTheme.label3)
                }
                Spacer()
                Text(column.dataType)
                    .font(.jbMono(11))
                    .foregroundStyle(KTEditorTheme.label3)
            }
            HStack(spacing: 8) {
                TextField("", text: binding.text)
                    .textFieldStyle(.roundedBorder)
                    .font(.jbMono(12.5))
                    .disabled(binding.wrappedValue.isNull)
                if column.isNullable {
                    Toggle("NULL", isOn: binding.isNull)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .foregroundStyle(KTEditorTheme.label2)
                }
            }
        }
    }

    private func fieldBinding(_ name: String) -> Binding<FieldState> {
        Binding(
            get: { fields[name] ?? FieldState(text: "", isNull: false) },
            set: { fields[name] = $0 }
        )
    }

    private func initFields() {
        var initial: [String: FieldState] = [:]
        for column in vm.columns {
            initial[column.name] = FieldState(text: "", isNull: false)
        }
        fields = initial
    }

    private func commit() {
        var values: [ColumnValue] = []
        for column in vm.columns {
            let field = fields[column.name] ?? FieldState(text: "", isNull: false)
            if field.isNull {
                values.append(ColumnValue(column: column.name, value: .null))
            } else if field.text.isEmpty && (column.defaultValue != nil || column.isNullable) {
                continue
            } else if !field.text.isEmpty {
                values.append(ColumnValue(column: column.name, value: .text(field.text)))
            }
        }
        Task {
            await vm.insertRow(values)
            dismiss()
        }
    }
}
