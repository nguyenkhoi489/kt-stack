import KTStackKit
import SwiftUI

/// Restore picker for a single backup set. Target is `.overwrite` (typed-name confirmation gates the
/// destructive path — DestructiveGuard never sees the provider DROP) or `.newDatabase`, where the
/// engine refuses collisions and the UI must explain so. Disabled when the connection is read-only.
struct RestoreSheet: View {
    @Environment(\.dismiss) private var dismiss

    enum Mode: Hashable { case overwrite, newDatabase }

    let set: BackupSet
    let isReadOnly: Bool
    let onConfirm: @MainActor (_ database: String, _ target: RestoreTarget) async -> Void

    @State private var selectedDatabase: String
    @State private var mode: Mode = .newDatabase
    @State private var newDatabaseName: String = ""
    @State private var typedConfirmation: String = ""
    @State private var submitting = false

    init(
        set: BackupSet,
        isReadOnly: Bool,
        onConfirm: @escaping @MainActor (_ database: String, _ target: RestoreTarget) async -> Void
    ) {
        self.set = set
        self.isReadOnly = isReadOnly
        self.onConfirm = onConfirm
        _selectedDatabase = State(initialValue: set.databases.first ?? "")
        _newDatabaseName = State(initialValue: (set.databases.first ?? "") + "_restored")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 460, height: 380)
    }

    private var header: some View {
        VStack(spacing: KDSpacing.space2) {
            Text("Restore from backup").font(KDFont.title)
            Text("\(set.kind.rawValue.uppercased()) · \(set.profileName)")
                .font(KDFont.footnote).foregroundStyle(.secondary)
        }
        .padding(KDSpacing.space3)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KDSpacing.space3) {
                if isReadOnly {
                    Label("This connection is read-only; restore is disabled.", systemImage: "lock")
                        .font(KDFont.footnote).foregroundStyle(.secondary)
                }
                databasePicker
                targetSection
                confirmationField
            }
            .padding(KDSpacing.space3)
        }
    }

    private var databasePicker: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space1) {
            Text("Database to restore").font(KDFont.headline)
            Picker("", selection: $selectedDatabase) {
                ForEach(set.databases, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space2) {
            Text("Restore to").font(KDFont.headline)
            Picker("", selection: $mode) {
                Text("New database").tag(Mode.newDatabase)
                Text("Overwrite source database").tag(Mode.overwrite)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            switch mode {
            case .newDatabase:
                TextField("New database name", text: $newDatabaseName)
                    .textFieldStyle(.roundedBorder).font(KDFont.mono)
                Text("If the chosen name already exists, the restore will refuse and ask you to pick another.")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
            case .overwrite:
                Text("This will DROP \"\(selectedDatabase)\" and reload it from the backup. The previous content cannot be recovered after the rollback window.")
                    .font(KDFont.footnote).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var confirmationField: some View {
        if mode == .overwrite {
            VStack(alignment: .leading, spacing: KDSpacing.space1) {
                Text("Type \"\(selectedDatabase)\" to confirm overwrite.")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
                TextField("", text: $typedConfirmation)
                    .textFieldStyle(.roundedBorder).font(KDFont.mono)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Restore") { run() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || submitting)
        }
        .padding(KDSpacing.space3)
    }

    private var canSubmit: Bool {
        guard !isReadOnly, !selectedDatabase.isEmpty else { return false }
        switch mode {
        case .newDatabase: return !newDatabaseName.trimmingCharacters(in: .whitespaces).isEmpty
        case .overwrite: return typedConfirmation == selectedDatabase
        }
    }

    private func run() {
        let database = selectedDatabase
        let target: RestoreTarget = switch mode {
        case .newDatabase: .newDatabase(newDatabaseName.trimmingCharacters(in: .whitespaces))
        case .overwrite: .overwrite
        }
        submitting = true
        Task {
            await onConfirm(database, target)
            submitting = false
            dismiss()
        }
    }
}
