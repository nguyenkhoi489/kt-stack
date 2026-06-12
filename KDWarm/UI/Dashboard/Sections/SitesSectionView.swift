import SwiftUI
import KDWarmKit

/// Sites dashboard: the list of registered sites + Add/Remove + the DNS automation bar
/// (replaces the Phase 2/3 manual `/etc/hosts` note). Observes the server (status), the registry
/// (site list) and the DNS service so it re-renders on any change.
struct SitesSectionView: View {
    /// Opens the Logs view filtered to a site's log (set by a row's "Logs" action).
    var onOpenLogs: (String?) -> Void = { _ in }

    @EnvironmentObject private var server: LocalServerController
    @EnvironmentObject private var dns: DNSAutomationService
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        SitesContent(server: server, registry: server.registry, dns: dns,
                     preferences: preferences, onOpenLogs: onOpenLogs)
    }
}

private struct SitesContent: View {
    @ObservedObject var server: LocalServerController
    @ObservedObject var registry: SiteRegistry
    @ObservedObject var dns: DNSAutomationService
    @ObservedObject var preferences: AppPreferences
    var onOpenLogs: (String?) -> Void
    @State private var showAddSheet = false

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
    }

    private var toolbar: some View {
        HStack(spacing: KDSpacing.space2) {
            Button(server.isRunning ? "Stop Server" : "Start Server") { server.toggle() }
                .disabled(server.isBusy)
            StatusPill(server.nginxStatus, text: server.isRunning ? "nginx" : "offline")
            Spacer()
            Button { showAddSheet = true } label: { Label("Add Site", systemImage: "plus") }
        }
        .padding(KDSpacing.space2)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(registry.sites) { site in
                    SiteRowView(
                        site: site,
                        availableVersions: server.availableVersions,
                        canOpen: server.isRunning,
                        onOpen: { open(site) },
                        onRemove: { registry.remove(site) },
                        onEditDomain: { try registry.editDomain(site, to: $0) },
                        onSetVersion: { registry.setPHPVersion(site, to: $0) },
                        onSetSecure: { server.setSiteSecure(site, $0) },
                        onOpenLogs: { onOpenLogs("site-\(site.domain)-access") })
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
