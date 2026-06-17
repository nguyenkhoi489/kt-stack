import SwiftUI
import KDWarmKit
import AppKit

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
    let restoreSheet: (BackupSet) -> AnyView

    @State private var sets: [BackupSet] = []
    @State private var restoringSet: BackupSet?

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
        .sheet(item: $restoringSet) { set in restoreSheet(set) }
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
        case .running(let message):
            HStack(spacing: KDSpacing.space2) {
                ProgressView().controlSize(.small)
                Text(message).font(KDFont.footnote)
            }
        case .done(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(KDFont.footnote).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(KDFont.footnote).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            backupActions
            Divider()
            listSection
        }
        .padding(KDSpacing.space3)
    }

    @ViewBuilder
    private var backupActions: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space2) {
            Text("Create backup").font(KDFont.headline)
            if let reason = unavailableReason {
                Label(reason, systemImage: "exclamationmark.circle")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
            } else {
                HStack(spacing: KDSpacing.space2) {
                    Button("Back up \"\(selectedDatabase ?? "current")\"") { onBackupCurrent() }
                        .disabled(!canBackup || selectedDatabase == nil || backupStatus.isRunning)
                    Button("Back up all databases") { onBackupAll() }
                        .disabled(!canBackup || backupStatus.isRunning)
                    Button("Import set…") { importSet() }
                }
            }
        }
    }

    @ViewBuilder
    private var listSection: some View {
        Text("History").font(KDFont.headline)
        if sets.isEmpty {
            EmptyStateView(symbol: "tray",
                           title: "No backups yet",
                           message: "Create a backup above to start the library.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: KDSpacing.space2) {
                    ForEach(sets) { row(for: $0) }
                }
            }
        }
    }

    @ViewBuilder
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

    // MARK: - Actions

    private func reload() { sets = session.library.list() }

    private func exportSet(_ set: BackupSet) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(set.profileName)-\(set.id.uuidString.prefix(8))"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onExport(set, url)
    }

    private func importSet() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { _ = try session.library.importSet(from: url); reload() }
        catch { onImportFailed(error.localizedDescription) }
    }

    private func revealInFinder(_ set: BackupSet) {
        NSWorkspace.shared.activateFileViewerSelecting([session.library.directory(for: set)])
    }

    // MARK: - Row formatting

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
        case .mysql:    return "cylinder.split.1x2"
        case .postgres: return "cylinder.split.1x2.fill"
        case .sqlite:   return "doc.text"
        case .mongodb:  return "leaf.fill"
        }
    }

}

private let backupRowDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium; f.timeStyle = .short
    return f
}()

private extension DatabaseViewModel.BackupStatus {
    var isRunning: Bool { if case .running = self { return true } else { return false } }
}
