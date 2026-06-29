import KTStackKit
import SwiftUI

struct CreateDatabaseSheet: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    @EnvironmentObject private var documentVM: DocumentViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var submitting = false

    private var isDocumentTrack: Bool {
        documentVM.selectedProfile?.kind == .mongodb
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 420, height: 240)
        .onAppear {
            if isDocumentTrack {
                documentVM.clearBackupStatus()
            } else {
                vm.clearDumpStatus()
            }
        }
    }

    private var header: some View {
        VStack(spacing: KDSpacing.space2) {
            Text("Create Database").font(KDFont.title)
            Text(activeProfileName)
                .font(KDFont.footnote).foregroundStyle(.secondary)
        }
        .padding(KDSpacing.space3)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            TextField("database_name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(KDFont.mono)
            statusRow
        }
        .padding(KDSpacing.space3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var statusRow: some View {
        if isDocumentTrack {
            backupStatusRow
        } else {
            dumpStatusRow
        }
    }

    @ViewBuilder
    private var dumpStatusRow: some View {
        switch vm.dumpStatus {
        case .idle: EmptyView()
        case .running: progressRow("Creating…")
        case let .done(message): successRow(message)
        case let .failed(message): failureRow(message)
        }
    }

    @ViewBuilder
    private var backupStatusRow: some View {
        switch documentVM.backupStatus {
        case .idle: EmptyView()
        case let .running(message): progressRow(message)
        case let .done(message): successRow(message)
        case let .failed(message): failureRow(message)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Create") { create() }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
        }
        .padding(KDSpacing.space3)
    }

    private func create() {
        guard !submitting else { return }
        submitting = true
        Task {
            let created: Bool = if isDocumentTrack {
                await documentVM.createDatabase(named: name)
            } else {
                await vm.createDatabase(named: name)
            }
            submitting = false
            if created { dismiss() }
        }
    }

    private var activeProfileName: String {
        (isDocumentTrack ? documentVM.selectedProfile : vm.selectedProfile)?.name ?? "No connection"
    }

    private func progressRow(_ message: String) -> some View {
        HStack(spacing: KDSpacing.space2) {
            ProgressView().controlSize(.small)
            Text(message).font(KDFont.footnote)
        }
    }

    private func successRow(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(KDFont.footnote).foregroundStyle(.green)
    }

    private func failureRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(KDFont.footnote).foregroundStyle(.orange)
    }
}
