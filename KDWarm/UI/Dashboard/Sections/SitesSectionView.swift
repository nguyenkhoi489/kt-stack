import SwiftUI
import KDWarmKit


struct SitesSectionView: View {
    
    var onOpenLogs: (String?) -> Void = { _ in }

    @EnvironmentObject private var server: LocalServerController
    @EnvironmentObject private var dns: DNSAutomationService
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var tunnels: TunnelManager

    var body: some View {
        SitesContent(server: server, registry: server.registry, dns: dns,
                     preferences: preferences, tunnels: tunnels, onOpenLogs: onOpenLogs)
    }
}

private struct SitesContent: View {
    @ObservedObject var server: LocalServerController
    @ObservedObject var registry: SiteRegistry
    @ObservedObject var dns: DNSAutomationService
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var tunnels: TunnelManager
    var onOpenLogs: (String?) -> Void
    @State private var showAddSheet = false
    @State private var showScanSheet = false
    @State private var showNewSheet = false
    @State private var showImportSheet = false
    @State private var searchText = ""

    private var filteredSites: [Site] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return registry.sites }
        return registry.sites.filter {
            $0.domain.localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if registry.sites.isEmpty {
                EmptyStateView(
                    symbol: "globe",
                    title: "No sites yet",
                    message: "Add a folder under \(preferences.sitesRootPath) to serve it at <name>.\(registry.tld).",
                    actionTitle: "Add Site…"
                ) { showAddSheet = true }
            } else {
                if registry.sites.count > 8 {
                    searchField
                    Divider()
                }
                list
            }
            if let error = server.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(KDFont.footnote)
                    .foregroundStyle(Color.KDStatus.warning)
                    .padding(KDSpacing.space2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            DNSStatusBar(dns: dns)
        }
        .navigationTitle("Sites")
        .sheet(isPresented: $showAddSheet) {
            AddSiteSheet(registry: registry, availableVersions: server.availableVersions,
                         sitesRoot: preferences.sitesRootURL)
        }
        .sheet(isPresented: $showScanSheet) {
            ScanImportSheet(registry: registry, sitesRoot: preferences.sitesRootURL)
        }
        .sheet(isPresented: $showNewSheet) {
            NewSiteSheet(registry: registry, availableVersions: server.availableVersions,
                         sitesRoot: preferences.sitesRootURL, tld: registry.tld)
        }
        .sheet(isPresented: $showImportSheet) {
            MigrateImportSheet(registry: registry, availableVersions: server.availableVersions)
        }
    }

    private var toolbar: some View {
        HStack(spacing: KDSpacing.space2) {
            Button(server.isRunning ? "Stop Server" : "Start Server") { server.toggle() }
                .disabled(server.isBusy)
            StatusPill(server.nginxStatus, text: server.isRunning ? "nginx" : "offline")
            Spacer()
            Button { showScanSheet = true } label: { Label("Scan…", systemImage: "folder.badge.gearshape") }
            Button { showImportSheet = true } label: { Label("Import…", systemImage: "square.and.arrow.down") }
            Button { showAddSheet = true } label: { Label("Add Site", systemImage: "plus") }
            Button { showNewSheet = true } label: { Label("New Site", systemImage: "sparkles") }
                .keyboardShortcut("n", modifiers: .command)
        }
        .padding(KDSpacing.space2)
    }

    private var searchField: some View {
        HStack(spacing: KDSpacing.space2) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search sites by name or domain", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .padding(KDSpacing.space2)
    }

    @ViewBuilder
    private var list: some View {
        if filteredSites.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                title: "No matching sites",
                message: "No site matches “\(searchText)”.",
                actionTitle: "Clear Search"
            ) { searchText = "" }
        } else {
            siteScroll
        }
    }

    private var siteScroll: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredSites) { site in
                    SiteRowView(
                        site: site,
                        availableVersions: server.availableVersions,
                        canOpen: server.isRunning,
                        onOpen: { open(site) },
                        onRemove: { registry.remove(site) },
                        onEditDomain: { try registry.editDomain(site, to: $0) },
                        onSetVersion: { registry.setPHPVersion(site, to: $0) },
                        onSetSecure: { server.setSiteSecure(site, $0) },
                        onOpenLogs: { onOpenLogs("site-\(site.domain)-access") },
                        shareStatus: tunnels.session(site.id)?.status ?? .idle,
                        onToggleShare: { on in
                            if on { tunnels.start(site: site) } else { tunnels.stop(site: site.id) }
                        })
                    Divider()
                }
            }
        }
    }

    private func open(_ site: Site) {
        let scheme = site.secure ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(site.domain)/") else { return }
        NSWorkspace.shared.open(url)
    }
}
