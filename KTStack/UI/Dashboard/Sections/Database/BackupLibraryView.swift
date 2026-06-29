import AppKit
import KTStackKit
import SwiftUI

/// Backup history + actions. The "create backup" form, the history list, and the per-set actions
/// (restore, delete, export) live behind the same sheet so the user can move between them without
/// stacking modals. Engine availability and read-only state both gate the destructive actions.
struct BackupLibraryView<VM: AnyObject>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let canBackup: Bool
    let unavailableReason: String?
    let isReadOnlyConnection: Bool
    let selectedDatabase: String?
    let activeProfileKind: DatabaseKind?
    let session: BackupSession
    let viewModel: VM
    let backupStatus: DatabaseViewModel.BackupStatus
    let onBackupCurrent: @MainActor () -> Void
    let onBackupAll: @MainActor () -> Void
    let onDelete: @MainActor (BackupSet) -> Void
    let onExport: @MainActor (BackupSet, URL) -> Void
    let onImportFailed: @MainActor (String) -> Void
    let onInstallTools: (@MainActor () -> Void)?
    let onRestoreAll: @MainActor (BackupSet) -> Void
    let restoreSheet: (BackupSet) -> AnyView

    @State private var sets: [BackupSet] = []
    @State private var restoringSet: BackupSet?
    @State private var confirmingRestoreAllSet: BackupSet?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 480)
        .onAppear { reload() }
        .onChange(of: backupStatus) { status in
            if case .done = status { reload() }
        }
        .sheet(item: $restoringSet) { set in restoreSheet(set) }
        .alert(
            "Restore All Databases?",
            isPresented: .init(
                get: { confirmingRestoreAllSet != nil },
                set: { _ in confirmingRestoreAllSet = nil }
            ),
            presenting: confirmingRestoreAllSet
        ) { set in
            Button("Restore All \(set.databases.count) Databases", role: .destructive) {
                onRestoreAll(set)
            }
            Button("Cancel", role: .cancel) {}
        } message: { set in
            Text("This will overwrite all \(set.databases.count) databases in \"\(set.profileName)\" with their backup versions. Data added after this backup was created will be lost.")
        }
    }

    private var header: some View {
        VStack(spacing: KDSpacing.space2) {
            Text(title).font(KDFont.title)
            statusRow
        }
        .padding(KDSpacing.space3)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch backupStatus {
        case .idle: EmptyView()
        case let .running(message):
            HStack(spacing: KDSpacing.space2) {
                ProgressView().controlSize(.small)
                Text(message).font(KDFont.footnote)
            }
        case let .done(message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(KDFont.footnote).foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(KDFont.footnote).foregroundStyle(.orange)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            backupActions
            Divider()
            listSection
        }
        .padding(KDSpacing.space3)
    }

    private var backupActions: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space2) {
            Text("Create backup").font(KDFont.headline)
            if let reason = unavailableReason {
                HStack(spacing: KDSpacing.space2) {
                    Label(reason, systemImage: "exclamationmark.circle")
                        .font(KDFont.footnote).foregroundStyle(.secondary)
                    if let onInstallTools, let title = installToolsTitle {
                        Button(title) { onInstallTools() }
                    }
                }
            }
            HStack(spacing: KDSpacing.space2) {
                Button("Back up \"\(selectedDatabase ?? "current")\"") { onBackupCurrent() }
                    .disabled(!canBackup || selectedDatabase == nil || backupStatus.isRunning)
                Button("Back up all databases") { onBackupAll() }
                    .disabled(!canBackup || backupStatus.isRunning)
                Button("Import set…") { importSet() }
            }
        }
    }

    private var installToolsTitle: String? {
        switch activeProfileKind {
        case .mysql: "Install MySQL…"
        case .postgres: "Install PostgreSQL…"
        default: nil
        }
    }

    @ViewBuilder
    private var listSection: some View {
        Text("History").font(KDFont.headline)
        if sets.isEmpty {
            EmptyStateView(
                symbol: "tray",
                title: "No backups yet",
                message: "Create a backup above to start the library."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: KDSpacing.space2) {
                    ForEach(sets) { row(for: $0) }
                }
            }
        }
    }

    private func row(for set: BackupSet) -> some View {
        HStack(alignment: .top, spacing: KDSpacing.space3) {
            Image(systemName: symbol(for: set.kind)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(set)).font(KDFont.body)
                Text(rowSubtitle(set)).font(KDFont.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Menu("Actions") {
                Button("Restore…") { restoringSet = set }
                    .disabled(activeProfileKind != set.kind || isReadOnlyConnection)
                if set.databases.count > 1 {
                    Button("Restore All Databases…") { confirmingRestoreAllSet = set }
                        .disabled(activeProfileKind != set.kind || isReadOnlyConnection)
                }
                Button("Export…") { exportSet(set) }
                Button("Reveal in Finder") { revealInFinder(set) }
                Divider()
                Button("Delete", role: .destructive) { onDelete(set); reload() }
            }
        }
        .padding(.vertical, KDSpacing.space1)
    }

    private var footer: some View {
        HStack {
            Button("Refresh") { reload() }
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(KDSpacing.space3)
    }

    private func reload() {
        sets = session.library.list()
    }

    private func exportSet(_ set: BackupSet) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: BackupLibrary.portableExtension) ?? .data,
        ]
        panel.nameFieldStringValue =
            "\(set.profileName)-\(set.id.uuidString.prefix(8)).\(BackupLibrary.portableExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onExport(set, url)
    }

    private func importSet() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .init(filenameExtension: BackupLibrary.portableExtension) ?? .data,
            .zip, .folder,
        ]
        panel.message = "Choose a .\(BackupLibrary.portableExtension) archive or a backup set folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { _ = try session.library.importSet(from: url); reload() }
        catch { onImportFailed(error.localizedDescription) }
    }

    private func revealInFinder(_ set: BackupSet) {
        NSWorkspace.shared.activateFileViewerSelecting([session.library.directory(for: set)])
    }

    private func rowTitle(_ set: BackupSet) -> String {
        if set.databases.count == 1 { return set.databases[0] }
        return "\(set.databases.count) databases"
    }

    private func rowSubtitle(_ set: BackupSet) -> String {
        let date = backupRowDateFormatter.string(from: set.createdAt)
        let size = ByteCountFormatter.string(fromByteCount: set.sizeBytes, countStyle: .file)
        return "\(set.kind.rawValue.uppercased()) · \(set.profileName) · \(date) · \(size)"
    }

    private func symbol(for kind: DatabaseKind) -> String {
        switch kind {
        case .mysql: "cylinder.split.1x2"
        case .postgres: "cylinder.split.1x2.fill"
        case .sqlite: "doc.text"
        case .mongodb: "leaf.fill"
        }
    }
}

private let backupRowDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium; f.timeStyle = .short
    return f
}()

private extension DatabaseViewModel.BackupStatus {
    var isRunning: Bool {
        if case .running = self { true } else { false }
    }
}
