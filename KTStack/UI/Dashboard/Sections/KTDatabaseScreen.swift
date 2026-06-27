import SwiftUI
import AppKit
import KTStackKit

struct KTDatabaseScreen: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var services: ServiceManager
    @EnvironmentObject private var overlay: KTOverlayCenter
    @ObservedObject var nav: DashboardNavigation

    let onOpenEditor: () -> Void

    enum Tab: Hashable { case servers, backups }

    @StateObject private var reachability = ServerReachabilityService()
    @State private var tab: Tab = .servers
    @State private var serverSearch = ""
    @State private var session = BackupSession.managed()
    @State private var backupSets: [BackupSet] = []
    @State private var reloadGeneration = 0
    @State private var showImportExport = false
    @State private var restoringSet: BackupSet?
    @State private var backingUpAll = false
    @State private var opening = false

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
        .task {
            reachability.configure(profiles: { connectionStore.allProfiles },
                                   managedRunning: { managedEngineRunning($0) })
            reachability.start()
            await reloadBackups()
        }
        .onChange(of: nav.activeItem) { item in
            if item == .database { reachability.start() } else { reachability.stop() }
        }
        .onDisappear { reachability.stop() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Database").font(KTType.screenTitle).tracking(KTType.screenTitleTracking).foregroundStyle(KTColor.ink)
            KTPill(text: "\(visibleProfiles.count) connections")
            if vm.connection == .connected, let active = vm.selectedProfile {
                KTBadge(text: "Active · \(active.name)", tint: KTEngineTint.of(active.kind.rawValue), radius: 6)
            }
            Spacer()
            KTButton(title: "Connect", systemImage: "link", kind: .secondary) { overlay.connectPresented = true }
            KTButton(title: "Import", systemImage: "square.and.arrow.down", kind: .secondary) { showImportExport = true }
                .disabled(vm.connection != .connected || !(vm.canDump || vm.canManualImport))
            KTButton(title: backingUpAll ? "Backing up…" : "Backup All", systemImage: "tray.and.arrow.down",
                     kind: .secondary, isLoading: backingUpAll) { backupAll() }
                .disabled(vm.connection != .connected || backingUpAll)
            KTButton(title: "New Database", systemImage: "plus", kind: .primary) { overlay.newDatabasePresented = true }
                .disabled(vm.connection != .connected || !vm.canCreateDatabase)
        }
    }

    private var tabBar: some View {
        KTSegmentedTabs(items: [.init(value: .servers, label: "Servers"), .init(value: .backups, label: "Backups")],
                        selection: $tab)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .servers: serversTab
        case .backups: backupsTab
        }
    }

    @ViewBuilder
    private var serversTab: some View {
        if visibleProfiles.isEmpty {
            emptyState(icon: "cylinder.split.1x2", title: "No connections yet",
                       message: "Add a database server to browse it. Bundled MySQL / PostgreSQL / MongoDB appear here once their engine is running.",
                       cta: ("Connect a server", "link", { overlay.connectPresented = true }))
        } else {
            VStack(spacing: 14) {
                KTSearchField(text: $serverSearch, placeholder: "Search connections…")
                let matches = filteredProfiles
                if matches.isEmpty {
                    emptyState(icon: "magnifyingglass", title: "No matches",
                               message: "No connection matches “\(serverSearch)”.")
                } else {
                    ScrollView { serverRows(matches) }
                }
            }
        }
    }

    private var visibleProfiles: [ConnectionProfile] {
        var seen = Set<String>()
        return connectionStore.allProfiles.filter { profile in
            let key = [profile.kind.rawValue, profile.name, profile.host, String(profile.port),
                       profile.user, profile.database, profile.filePath ?? ""].joined(separator: "\u{1F}")
            return seen.insert(key).inserted
        }
    }

    private var filteredProfiles: [ConnectionProfile] {
        let query = serverSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return visibleProfiles }
        return visibleProfiles.filter {
            $0.name.range(of: query, options: .caseInsensitive) != nil
                || $0.host.range(of: query, options: .caseInsensitive) != nil
        }
    }

    private func serverRows(_ profiles: [ConnectionProfile]) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(profiles) { profile in
                KTServerRow(profile: profile,
                            status: reachability.currentStatus(for: profile.id),
                            databaseCount: databaseCount(for: profile),
                            onOpen: { open(profile) },
                            onOpenV2: { DatabaseV2WindowController.shared.present(profile: profile) },
                            onBackup: { backupServer(profile) },
                            onRestore: { tab = .backups })
            }
        }
    }

    private func databaseCount(for profile: ConnectionProfile) -> Int? {
        guard vm.connection == .connected, vm.selectedProfile?.id == profile.id else { return nil }
        return vm.databases.count
    }

    @ViewBuilder
    private var backupsTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("\(backupSets.count) backups").font(.jbMono(13)).foregroundStyle(Color(hex: 0x8E8E93))
                Spacer()
                KTButton(title: backingUpAll ? "Backing up…" : "Backup All Now", systemImage: "tray.and.arrow.down",
                         kind: .primary, isLoading: backingUpAll) { backupAll() }
                    .disabled(vm.connection != .connected || backingUpAll)
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

    private func emptyState(icon: String, title: String, message: String,
                            cta: (title: String, systemImage: String, action: () -> Void)? = nil) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 42, weight: .light)).foregroundStyle(KTColor.faint)
            Text(title).font(.jbMono(16, .regular)).foregroundStyle(KTColor.ink3)
            Text(message).font(.jbMono(12.5)).foregroundStyle(KTColor.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            if let cta {
                KTButton(title: cta.title, systemImage: cta.systemImage, kind: .primary, action: cta.action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func managedEngineRunning(_ kind: DatabaseKind) -> Bool {
        let serviceKind: ServiceKind
        switch kind {
        case .mysql:    serviceKind = .mysql
        case .postgres: serviceKind = .postgres
        case .mongodb:  serviceKind = .mongodb
        case .sqlite:   return false
        }
        return services.snapshots.first { $0.kind == serviceKind }?.status == .running
    }

    private func open(_ profile: ConnectionProfile) {
        guard !opening else { return }
        opening = true
        Task {
            await vm.select(profile: profile)
            defer { opening = false }
            guard vm.connection == .connected else {
                if case .failed(let error) = vm.connection { overlay.toast(error.message) }
                return
            }
            if let database = vm.resolvePreferredDatabase(for: profile) {
                await vm.select(database: database)
            } else {
                overlay.toast("Connected to “\(profile.name)” — no databases found")
            }
            onOpenEditor()
        }
    }

    private func backupServer(_ profile: ConnectionProfile) {
        Task {
            if vm.selectedProfile?.id != profile.id || vm.connection != .connected {
                await vm.select(profile: profile)
            }
            guard vm.connection == .connected else {
                if case .failed(let error) = vm.connection { overlay.toast(error.message) }
                return
            }
            let set = await vm.backupAllDatabases(session: session)
            await reloadBackups()
            if set != nil { overlay.toast("Backed up “\(profile.name)”") }
        }
    }

    private func backupAll() {
        guard !backingUpAll else { return }
        backingUpAll = true
        Task {
            let set = await vm.backupAllDatabases(session: session)
            await reloadBackups()
            backingUpAll = false
            if set != nil { overlay.toast("Backup complete") }
        }
    }

    private func confirmDeleteBackup(_ set: BackupSet) {
        overlay.confirm(title: "Delete backup?",
                        message: "Permanently delete this backup. This cannot be undone.",
                        okLabel: "Delete", danger: true) {
            vm.deleteBackup(set, session: session)
            Task { await reloadBackups() }
            overlay.toast("Backup deleted")
        }
    }

    private func download(_ set: BackupSet) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(set.databases.first ?? "backup").zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        vm.exportBackup(set, to: url, session: session)
    }

    private func reloadBackups() async {
        let gen = reloadGeneration &+ 1
        reloadGeneration = gen
        let session = session
        let sets = await Task.detached { session.library.list() }.value
        guard gen == reloadGeneration else { return }
        backupSets = sets.sorted { $0.createdAt > $1.createdAt }
    }
}
