import SwiftUI
import AppKit
import KTStackKit

struct KTDatabaseScreen: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var services: ServiceManager
    @EnvironmentObject private var overlay: KTOverlayCenter

    enum Tab: Hashable { case databases, backups }

    @State private var tab: Tab = .databases
    @State private var session = BackupSession.managed()
    @State private var backupSets: [BackupSet] = []
    @State private var showConnect = false
    @State private var showNewDatabase = false
    @State private var showImportExport = false
    @State private var restoringSet: BackupSet?
    @State private var showEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, KTSpacing.screenGutter).padding(.top, 18)
            tabBar.padding(.horizontal, KTSpacing.screenGutter).padding(.top, 16)
            content.padding(.horizontal, KTSpacing.screenGutter).padding(.top, 16).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(KTColor.contentBg)
        .sheet(isPresented: $showImportExport) { ImportExportSheet() }
        .sheet(item: $restoringSet) { set in
            RestoreSheet(set: set, isReadOnly: vm.isReadOnlyConnection) { db, target in
                _ = await vm.restoreBackup(set, database: db, target: target, session: session)
            }
        }
        .task { await autoConnectIfNeeded(); reloadBackups() }
        .overlay { editorOverlay }
        .overlay { connectOverlay }
        .overlay { newDatabaseOverlay }
        .animation(.easeOut(duration: 0.15), value: showEditor)
        .animation(.easeOut(duration: 0.15), value: showConnect)
        .animation(.easeOut(duration: 0.15), value: showNewDatabase)
    }

    @ViewBuilder
    private var editorOverlay: some View {
        if showEditor {
            KTDatabaseEditorModal(onClose: { showEditor = false }).transition(.opacity)
        }
    }

    @ViewBuilder
    private var connectOverlay: some View {
        if showConnect {
            KTConnectModal(onClose: { showConnect = false },
                           onConnected: { name in
                               showConnect = false
                               reloadBackups()
                               overlay.toast("Connected to \(name)")
                           })
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var newDatabaseOverlay: some View {
        if showNewDatabase {
            KTNewDatabaseModal(onClose: { showNewDatabase = false },
                               onCreated: { name in
                                   showNewDatabase = false
                                   overlay.toast("Database “\(name)” created")
                               })
                .transition(.opacity)
        }
    }

    private func confirmDeleteBackup(_ set: BackupSet) {
        overlay.confirm(title: "Delete backup?",
                        message: "Permanently delete this backup. This cannot be undone.",
                        okLabel: "Delete", danger: true) {
            vm.deleteBackup(set, session: session)
            reloadBackups()
            overlay.toast("Backup deleted")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Database").font(KTType.screenTitle).tracking(KTType.screenTitleTracking).foregroundStyle(KTColor.ink)
            KTPill(text: "\(vm.databases.count) databases")
            Spacer()
            KTButton(title: "Connect", systemImage: "link", kind: .secondary) { showConnect = true }
            KTButton(title: "Backup All", systemImage: "tray.and.arrow.down", kind: .secondary) { backupAll() }
                .disabled(vm.connection != .connected)
            KTButton(title: "New Database", systemImage: "plus", kind: .primary) { showNewDatabase = true }
                .disabled(vm.connection != .connected || !vm.canCreateDatabase)
        }
    }

    private var tabBar: some View {
        KTSegmentedTabs(items: [.init(value: .databases, label: "Databases"), .init(value: .backups, label: "Backups")],
                        selection: $tab)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .databases: databasesTab
        case .backups: backupsTab
        }
    }

    @ViewBuilder
    private var databasesTab: some View {
        if vm.connection == .connected {
            if vm.databases.isEmpty {
                emptyState(icon: "cylinder.split.1x2", title: "No databases", message: "Create one to get started.")
            } else {
                ScrollView { KTListContainer { databaseRows } }
            }
        } else {
            connectionGate
        }
    }

    private var databaseRows: some View {
        let kind = vm.selectedProfile?.kind ?? .mysql
        return VStack(spacing: 0) {
            ForEach(Array(vm.databases.enumerated()), id: \.element.id) { index, db in
                KTDatabaseRow(name: db.name, kind: kind,
                              onOpen: { open(db.name) },
                              onBackup: { backup(db.name) },
                              onExport: { exportSQL(db.name) },
                              onRestore: { tab = .backups })
                if index < vm.databases.count - 1 {
                    Rectangle().fill(KTColor.sepFaint).frame(height: 0.5).padding(.leading, 18)
                }
            }
        }
    }

    @ViewBuilder
    private var backupsTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(backupSets.count) backups").font(.system(size: 13)).foregroundStyle(Color(hex: 0x8E8E93))
                Spacer()
                KTButton(title: "Backup All Now", systemImage: "tray.and.arrow.down", kind: .primary) { backupAll() }
                    .disabled(vm.connection != .connected)
            }
            .padding(.bottom, 14)
            if backupSets.isEmpty {
                emptyState(icon: "archivebox", title: "No backups yet", message: "Run a backup to protect your databases.")
            } else {
                ScrollView {
                    KTListContainer {
                        VStack(spacing: 0) {
                            ForEach(Array(backupSets.enumerated()), id: \.element.id) { index, set in
                                KTBackupRow(backup: set,
                                            onRestore: { restoringSet = set },
                                            onDownload: { download(set) },
                                            onDelete: { confirmDeleteBackup(set) })
                                if index < backupSets.count - 1 {
                                    Rectangle().fill(KTColor.sepFaint).frame(height: 0.5).padding(.leading, 18)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var connectionGate: some View {
        VStack(spacing: 10) {
            Image(systemName: "cylinder.split.1x2").font(.system(size: 46, weight: .light)).foregroundStyle(KTColor.faint)
            Text(gateTitle).font(.system(size: 17, weight: .semibold)).foregroundStyle(KTColor.ink3)
            Text(gateMessage).font(.system(size: 13)).foregroundStyle(KTColor.muted).multilineTextAlignment(.center)
            KTButton(title: "Connect", systemImage: "link", kind: .primary) { showConnect = true }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gateTitle: String {
        if case .connecting = vm.connection { return "Connecting…" }
        return "Connect to a database"
    }

    private var gateMessage: String {
        if case .failed(let error) = vm.connection { return error.message }
        return "Choose an engine and enter your connection details to browse databases."
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 46, weight: .light)).foregroundStyle(KTColor.faint)
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(KTColor.ink3)
            Text(message).font(.system(size: 13)).foregroundStyle(KTColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func autoConnectIfNeeded() async {
        guard vm.selectedProfile == nil, vm.connection == .idle,
              let profile = connectionStore.allProfiles.first else { return }
        await vm.select(profile: profile)
    }

    private func open(_ name: String) {
        Task {
            await vm.select(database: name)
            showEditor = true
        }
    }

    private func backup(_ name: String) {
        Task {
            let set = await vm.backupDatabase(name, session: session)
            reloadBackups()
            if set != nil { overlay.toast("Backed up “\(name)”") }
        }
    }

    private func backupAll() {
        Task {
            let set = await vm.backupAllDatabases(session: session)
            reloadBackups()
            if set != nil { overlay.toast("Backup complete") }
        }
    }

    private func exportSQL(_ name: String) {
        Task {
            await vm.select(database: name)
            showImportExport = true
        }
    }

    private func download(_ set: BackupSet) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(set.databases.first ?? "backup").zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        vm.exportBackup(set, to: url, session: session)
    }

    private func reloadBackups() {
        backupSets = session.library.list().sorted { $0.createdAt > $1.createdAt }
    }
}
