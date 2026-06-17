import SwiftUI
import KDWarmKit

struct DatabaseSectionView: View {
    var inWindow = false

    @EnvironmentObject private var vm: DatabaseViewModel
    @EnvironmentObject private var documentVM: DocumentViewModel
    @EnvironmentObject private var services: ServiceManager
    @Environment(\.openWindow) private var openWindow
    @State private var rightTab: RightTab = .data
    @State private var showingImportExport = false
    @State private var showingBackups = false
    @State private var backupSession = BackupSession.managed()

    enum RightTab: String, CaseIterable, Identifiable {
        case data = "Data"
        case structure = "Structure"
        case query = "Query"
        var id: String { rawValue }
    }

    private var isDocumentTrack: Bool { documentVM.selectedProfile != nil }

    private func openBrowserWindow() { openWindow(id: DatabaseWindow.windowID) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                if !inWindow {
                    ConnectionSidebarView()
                }
                if isDocumentTrack {
                    documentTrack
                } else {
                    relationalTrack
                }
            }
        }
        .navigationTitle("Database")
        .sheet(isPresented: $showingImportExport) { ImportExportSheet() }
        .sheet(isPresented: $showingBackups) { backupsSheet }
    }

    @ViewBuilder
    private var backupsSheet: some View {
        if isDocumentTrack {
            BackupLibraryView<DocumentViewModel>(
                title: "Backups",
                canBackup: documentVM.canBackup,
                unavailableReason: documentVM.backupUnavailableReason,
                isReadOnlyConnection: documentVM.isReadOnlyConnection,
                selectedDatabase: documentVM.selectedDatabase,
                activeProfileKind: documentVM.selectedProfile?.kind,
                session: backupSession,
                viewModel: documentVM,
                backupStatus: documentVM.backupStatus,
                onBackupCurrent: {
                    guard let db = documentVM.selectedDatabase else { return }
                    Task { _ = await documentVM.backupDatabase(db, session: backupSession) }
                },
                onBackupAll: {
                    Task { _ = await documentVM.backupAllDatabases(session: backupSession) }
                },
                onDelete: { documentVM.deleteBackup($0, session: backupSession) },
                onExport: { documentVM.exportBackup($0, to: $1, session: backupSession) },
                onImportFailed: { documentVM.failBackupStatus("Import failed: \($0)") },
                restoreSheet: { set in
                    AnyView(RestoreSheet(set: set, isReadOnly: documentVM.isReadOnlyConnection) { db, target in
                        _ = await documentVM.restoreBackup(set, database: db, target: target,
                                                            session: backupSession)
                    })
                })
        } else {
            BackupLibraryView<DatabaseViewModel>(
                title: "Backups",
                canBackup: vm.canBackup,
                unavailableReason: vm.backupUnavailableReason,
                isReadOnlyConnection: vm.isReadOnlyConnection,
                selectedDatabase: vm.selectedDatabase,
                activeProfileKind: vm.selectedProfile?.kind,
                session: backupSession,
                viewModel: vm,
                backupStatus: vm.backupStatus,
                onBackupCurrent: {
                    guard let db = vm.selectedDatabase else { return }
                    Task { _ = await vm.backupDatabase(db, session: backupSession) }
                },
                onBackupAll: {
                    Task { _ = await vm.backupAllDatabases(session: backupSession) }
                },
                onDelete: { vm.deleteBackup($0, session: backupSession) },
                onExport: { vm.exportBackup($0, to: $1, session: backupSession) },
                onImportFailed: { vm.failBackupStatus("Import failed: \($0)") },
                restoreSheet: { set in
                    AnyView(RestoreSheet(set: set, isReadOnly: vm.isReadOnlyConnection) { db, target in
                        _ = await vm.restoreBackup(set, database: db, target: target,
                                                    session: backupSession)
                    })
                })
        }
    }

    @ViewBuilder
    private var relationalTrack: some View {
        if inWindow {
            SchemaTreeView(onlySelectedDatabase: true)
            rightPane.frame(minWidth: 360)
        } else {
            SchemaTreeView(onSelectDatabase: openBrowserWindow)
            dashboardRightPane.frame(minWidth: 320)
        }
    }

    @ViewBuilder
    private var documentTrack: some View {
        if inWindow {
            DocumentSectionContent()
        } else if documentVM.connection == .connected {
            CollectionTreeView(onSelectDatabase: openBrowserWindow)
            launcherPane.frame(minWidth: 320)
        } else {
            DocumentSectionContent()
        }
    }

    @ViewBuilder
    private var dashboardRightPane: some View {
        switch vm.connection {
        case .connected: launcherPane
        default:         connectionGate
        }
    }

    private var launcherPane: some View {
        EmptyStateView(symbol: "macwindow.on.rectangle",
                       title: "Opens in its own window",
                       message: "Pick a database to browse its tables and data in a full-width window.",
                       actionTitle: "Open Database Window",
                       action: openBrowserWindow)
    }

    private var toolbar: some View {
        HStack(spacing: KDSpacing.space3) {
            Text(activeProfileName).font(KDFont.headline)
            connectionStatus
            Spacer()
            if inWindow {
                Button { showingBackups = true } label: {
                    Image(systemName: "externaldrive.badge.timemachine")
                }
                .help("Backups…")
                .disabled(!isDocumentTrack && vm.connection != .connected)
                .disabled(isDocumentTrack && documentVM.connection != .connected)
            }
            if inWindow && !isDocumentTrack {
                Button { showingImportExport = true } label: {
                    Image(systemName: "square.and.arrow.up.on.square")
                }
                .help("Import / Export…")
                .disabled(vm.connection != .connected || vm.selectedDatabase == nil)
                Picker("", selection: $rightTab) {
                    ForEach(RightTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                .disabled(vm.connection != .connected)
            }
        }
        .padding(KDSpacing.space3)
    }

    private var activeProfileName: String {
        (isDocumentTrack ? documentVM.selectedProfile : vm.selectedProfile)?.name ?? "No connection"
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if isDocumentTrack {
            documentConnectionStatus
        } else {
            relationalConnectionStatus
        }
    }

    @ViewBuilder
    private var documentConnectionStatus: some View {
        switch documentVM.connection {
        case .connecting:
            HStack(spacing: KDSpacing.space1) {
                ProgressView().controlSize(.small)
                Text("Connecting…").font(KDFont.footnote).foregroundStyle(.secondary)
            }
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(KDFont.footnote).foregroundStyle(.green)
        case .failed:
            Label("Disconnected", systemImage: "exclamationmark.triangle.fill")
                .font(KDFont.footnote).foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var relationalConnectionStatus: some View {
        switch vm.connection {
        case .connecting:
            HStack(spacing: KDSpacing.space1) {
                ProgressView().controlSize(.small)
                Text("Connecting…").font(KDFont.footnote).foregroundStyle(.secondary)
            }
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(KDFont.footnote).foregroundStyle(.green)
        case .failed:
            Label("Disconnected", systemImage: "exclamationmark.triangle.fill")
                .font(KDFont.footnote).foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var rightPane: some View {
        switch vm.connection {
        case .connected:
            switch rightTab {
            case .data:      TableDataView()
            case .structure: TableStructureView()
            case .query:     QueryEditorView()
            }
        default:
            connectionGate
        }
    }

    @ViewBuilder
    private var connectionGate: some View {
        switch vm.connection {
        case .connecting:
            ProgressView("Connecting…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            failureGate(error)
        default:
            EmptyStateView(symbol: "cylinder.split.1x2",
                           title: "Database",
                           message: "Pick a connection on the left to browse tables and run SQL.")
        }
    }

    @ViewBuilder
    private func failureGate(_ error: DatabaseError) -> some View {
        switch error {
        case .engineNotInstalled:
            EmptyStateView(symbol: "shippingbox",
                           title: "MySQL isn’t installed",
                           message: "Install the managed MySQL engine, then reconnect.",
                           actionTitle: "Install MySQL…",
                           action: { services.install(.mysql) })
        case .engineNotRunning:
            EmptyStateView(symbol: "play.circle",
                           title: "MySQL isn’t running",
                           message: "Start the MySQL engine, then reconnect.",
                           actionTitle: "Start MySQL",
                           action: { services.toggle(.mysql) })
        default:
            EmptyStateView(symbol: "exclamationmark.triangle",
                           title: "Connection failed",
                           message: error.message,
                           actionTitle: "Retry",
                           action: retry)
        }
    }

    private func retry() {
        guard let profile = vm.selectedProfile else { return }
        Task { await vm.select(profile: profile) }
    }
}
