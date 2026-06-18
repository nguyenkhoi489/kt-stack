import SwiftUI
import KDWarmKit

struct DropDatabaseConfirmationSheet: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    @Environment(\.dismiss) private var dismiss

    let database: DatabaseInfo

    @State private var typedName = ""
    @State private var submitting = false

    private var databaseName: String { database.name }
    private var canRun: Bool { typedName == databaseName && !submitting && !vm.isBusy }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 460, height: 300)
        .onAppear { vm.clearDDLError() }
    }

    private var header: some View {
        VStack(spacing: KDSpacing.space2) {
            Text("Drop Database").font(KDFont.title)
            Text(databaseName)
                .font(KDFont.footnote).foregroundStyle(.secondary)
        }
        .padding(KDSpacing.space3)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Text("This will permanently drop \"\(databaseName)\".")
                .font(KDFont.footnote).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: KDSpacing.space1) {
                Text("Type \"\(databaseName)\" to confirm.")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
                TextField("", text: $typedName)
                    .textFieldStyle(.roundedBorder)
                    .font(KDFont.mono)
            }
            statusRow
        }
        .padding(KDSpacing.space3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var statusRow: some View {
        if submitting || vm.isBusy {
            HStack(spacing: KDSpacing.space2) {
                ProgressView().controlSize(.small)
                Text("Dropping \(databaseName)…").font(KDFont.footnote)
            }
        } else if let error = vm.ddlError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(KDFont.footnote).foregroundStyle(.orange)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { cancel() }.keyboardShortcut(.cancelAction)
            Button("Run") { run() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canRun)
        }
        .padding(KDSpacing.space3)
    }

    private func cancel() {
        guard !submitting && !vm.isBusy else { return }
        vm.cancelDDL()
        vm.clearDDLError()
        dismiss()
    }

    private func run() {
        guard canRun else { return }
        vm.prepareDropDatabase(databaseName)
        submitting = true
        Task {
            let dropped = await vm.confirmDropDatabase(databaseName)
            submitting = false
            if dropped { dismiss() }
        }
    }
}
