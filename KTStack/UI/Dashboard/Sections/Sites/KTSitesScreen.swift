import SwiftUI
import AppKit
import KTStackKit

struct KTSitesScreen: View {
    var onOpenLogs: (String?) -> Void = { _ in }
    var onNavigate: (SidebarItem) -> Void = { _ in }

    @EnvironmentObject private var server: LocalServerController
    @EnvironmentObject private var dns: DNSAutomationService
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var tunnels: TunnelManager

    var body: some View {
        KTSitesContent(server: server, registry: server.registry, dns: dns,
                       preferences: preferences, tunnels: tunnels,
                       onOpenLogs: onOpenLogs, onNavigate: onNavigate)
    }
}

private struct KTSitesContent: View {
    @ObservedObject var server: LocalServerController
    @ObservedObject var registry: SiteRegistry
    @ObservedObject var dns: DNSAutomationService
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var tunnels: TunnelManager
    var onOpenLogs: (String?) -> Void
    var onNavigate: (SidebarItem) -> Void

    @EnvironmentObject private var overlay: KTOverlayCenter

    @State private var searchText = ""
    @State private var gridView = false
    @State private var showScan = false
    @State private var showImport = false
    @State private var restoreSite: Site?
    @State private var removingSiteID: UUID?
    @State private var actionError: String?

    private var filteredSites: [Site] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return registry.sites }
        return registry.sites.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.domain.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            KTSitesHeader(siteCount: registry.sites.count,
                          onScan: { showScan = true },
                          onImport: { showImport = true },
                          onNewSite: { overlay.newSitePresented = true })
                .padding(.horizontal, KTSpacing.screenGutter)
                .padding(.top, 18)

            serverStatusRow
                .padding(.horizontal, KTSpacing.screenGutter)
                .padding(.top, 14)

            toolbar
                .padding(.horizontal, KTSpacing.screenGutter)
                .padding(.top, 16)

            content
                .padding(.horizontal, KTSpacing.screenGutter)
                .padding(.top, 14)

            if let actionError = server.lastError ?? actionError {
                Text(actionError)
                    .font(.jbMono(12))
                    .foregroundStyle(KTColor.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, KTSpacing.screenGutter)
                    .padding(.top, 6)
            }

            KTSitesDNSFooter(dns: dns, tld: registry.tld)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ktTooltipHost()
        .background(KTColor.contentBg)
        .sheet(isPresented: $showScan) { ScanImportSheet(registry: registry, sitesRoot: preferences.sitesRootURL) }
        .sheet(isPresented: $showImport) { MigrateImportSheet(registry: registry, availableVersions: server.availableVersions) }
        .sheet(item: $restoreSite) { RestoreBackupSheet(site: $0, registry: registry, server: server) }
    }

    private var serverStatusRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                KTDot(color: server.isRunning ? KTColor.runDot : KTColor.stopDot)
                Text("Server: \(server.isRunning ? "Running" : "Stopped")")
                    .font(.jbMono(13, .medium))
                    .foregroundStyle(server.isRunning ? KTColor.online : KTColor.muted)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Capsule().fill((server.isRunning ? KTColor.runDot : KTColor.stopDot).opacity(0.12)))

            KTButton(title: server.isRunning ? "Stop Server" : "Start Server", kind: .secondary) { server.toggle() }
                .disabled(server.isBusy)
            Spacer()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            KTSearchField(text: $searchText, placeholder: "Search sites by name or domain…")
            HStack(spacing: 2) {
                viewToggle(systemImage: "square.grid.2x2", active: gridView) { gridView = true }
                viewToggle(systemImage: "list.bullet", active: !gridView) { gridView = false }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: KTRadius.segment, style: .continuous).fill(KTColor.segmentBg))
        }
    }

    private func viewToggle(systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? KTColor.ink : KTColor.ink3)
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Color.white : Color.clear)
                    .shadow(color: active ? .black.opacity(0.10) : .clear, radius: 1.5, y: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if registry.sites.isEmpty {
            emptyState(title: "No sites yet", message: "Add a folder under \(preferences.sitesRootPath) to serve it at <name>.\(registry.tld).")
        } else if filteredSites.isEmpty {
            emptyState(title: "No matching sites", message: "No site matches “\(searchText)”.")
        } else if gridView {
            ScrollView { grid.padding(.top, 2).padding(.horizontal, 2).padding(.bottom, 4) }
        } else {
            KTListContainer { ScrollView { list } }
        }
    }

    private var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredSites.enumerated()), id: \.element.id) { index, site in
                KTSiteListRow(site: site, availableVersions: server.availableVersions,
                              canOpen: server.isRunning, isSharing: isSharing(site),
                              shareStarting: isStartingShare(site), shareURL: shareURL(site),
                              onOpen: { KTSiteActions.openInBrowser(site) },
                              onSetVersion: { registry.setPHPVersion(site, to: $0) },
                              onSetSecure: { server.setSiteSecure(site, $0) },
                              onEditDomain: { try registry.editDomain(site, to: $0) },
                              onOpenLogs: { onOpenLogs("site-\(site.domain)-access") },
                              onToggleShare: { toggleShare(site, $0) },
                              onRemove: { confirmRemove(site) },
                              onError: { actionError = $0 },
                              onOpenRuntimes: { onNavigate(.runtimes) },
                              onRestore: { restoreSite = site })
                if index < filteredSites.count - 1 {
                    Rectangle().fill(KTColor.sepFaint).frame(height: 0.5).padding(.leading, 16)
                }
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 252), spacing: 14)], spacing: 14) {
            ForEach(filteredSites) { site in
                KTSiteGridCard(site: site, availableVersions: server.availableVersions,
                               canOpen: server.isRunning, isSharing: isSharing(site),
                               shareStarting: isStartingShare(site), shareURL: shareURL(site),
                               onOpen: { KTSiteActions.openInBrowser(site) },
                               onSetVersion: { registry.setPHPVersion(site, to: $0) },
                               onSetSecure: { server.setSiteSecure(site, $0) },
                               onOpenLogs: { onOpenLogs("site-\(site.domain)-access") },
                               onToggleShare: { toggleShare(site, $0) },
                               onRemove: { confirmRemove(site) },
                               onError: { actionError = $0 },
                               onRestore: { restoreSite = site })
            }
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "globe").font(.system(size: 46, weight: .light)).foregroundStyle(KTColor.faint)
            Text(title).font(.jbMono(17, .regular)).foregroundStyle(KTColor.ink3)
            Text(message).font(.jbMono(13)).foregroundStyle(KTColor.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func isSharing(_ site: Site) -> Bool {
        let status = tunnels.session(site.id)?.status ?? .idle
        return status != .idle
    }

    private func shareURL(_ site: Site) -> URL? {
        tunnels.session(site.id)?.status.publicURL
    }

    private func isStartingShare(_ site: Site) -> Bool {
        tunnels.session(site.id)?.status == .starting
    }

    private func toggleShare(_ site: Site, _ on: Bool) {
        if on { tunnels.start(site: site) } else { tunnels.stop(site: site.id) }
    }

    private func confirmRemove(_ site: Site) {
        overlay.confirm(title: "Remove \(site.domain)?", message: removeMessage(site),
                        okLabel: "Remove Site", danger: true) { remove(site) }
    }

    private func removeMessage(_ site: Site) -> String {
        if let db = site.databaseName {
            return "This permanently deletes \(site.path), drops the MySQL database “\(db)”, and removes the site from KTStack. This cannot be undone."
        }
        return "This permanently deletes \(site.path) and removes the site from KTStack. This cannot be undone."
    }

    private func remove(_ site: Site) {
        guard removingSiteID == nil else { return }
        removingSiteID = site.id
        actionError = nil
        Task {
            do {
                let coordinator = SiteRemovalCoordinator(
                    deleteFolder: { site in try await MainActor.run { try registry.deleteFolderForRemoval(site) } },
                    dropDatabase: { name in
                        let paths = AppSupportPaths()
                        let mysql = MySQLController(paths: paths, agents: LaunchAgentManager(paths: paths))
                        let database = DatabaseProvisioner(ensureEngine: { try await mysql.start() })
                        try await database.dropDatabase(name)
                    },
                    removeRecord: { site in await MainActor.run { registry.remove(site) } })
                try await coordinator.remove(site)
                overlay.toast("Removed \(site.domain)")
            } catch {
                actionError = "Couldn't remove \(site.domain): \(error.localizedDescription)"
            }
            removingSiteID = nil
        }
    }
}
