import KTStackKit
import SwiftUI

struct KTServicesScreen: View {
    var onNavigate: (SidebarItem) -> Void = { _ in }
    var onOpenLogs: (String?) -> Void = { _ in }

    @EnvironmentObject private var services: ServiceManager
    @EnvironmentObject private var server: LocalServerController
    @EnvironmentObject private var dns: DNSAutomationService
    @EnvironmentObject private var overlay: KTOverlayCenter
    @EnvironmentObject private var caTrust: CATrustService

    @State private var editingNginxConf: NginxConfEditToken?
    // Cached so the metric-driven body (re-runs ~0.9s while a service is live) doesn't re-list the
    // runtime dirs each tick. Installed set / active version only change on install/uninstall
    // (Runtimes screen) or a switch here, so refresh on appear and after setActive.
    @State private var dbVersions: [ServiceKind: (installed: [String], active: String?)] = [:]

    private struct NginxConfEditToken: Identifiable { let id = UUID() }

    private var caExists: Bool {
        caTrust.status != .notInstalled
    }

    private var caTrusted: Bool {
        caTrust.isTrusted
    }

    private static let groups: [(title: String, kinds: [ServiceKind])] = [
        ("Core Proxy & DNS", [.nginx, .dnsmasq]),
        ("Runtimes", [.phpFpm]),
        ("Mail", [.mailpit]),
    ]

    private static let dbKinds: [ServiceKind] = [.mysql, .postgres, .redis, .mongodb]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, KTSpacing.screenGutter).padding(.top, 18)
            Text("Background services powering your local environment.")
                .font(.jbMono(13.5)).foregroundStyle(Color(hex: 0x8E8E93))
                .padding(.horizontal, KTSpacing.screenGutter).padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !banners.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(banners) { banner in
                                ServiceErrorBanner(
                                    status: banner.status,
                                    title: banner.title,
                                    message: banner.message,
                                    ctaTitle: banner.ctaTitle,
                                    action: banner.action
                                )
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    ForEach(Self.groups, id: \.title) { group in
                        standardGroup(group)
                        // DB/cache engines: run + swap-installed here; install/uninstall on Runtimes.
                        if group.title == "Runtimes" { dbGroup }
                    }
                }
                .padding(.horizontal, KTSpacing.screenGutter)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(KTColor.contentBg)
        .sheet(item: $editingNginxConf) { _ in
            NginxIncludeEditorSheet()
                .environmentObject(server)
        }
        .task { await caTrust.refreshAsync() }
        .onAppear { refreshDBVersions() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Services").font(KTType.screenTitle).tracking(KTType.screenTitleTracking).foregroundStyle(KTColor.ink)
            Spacer()
            KTButton(title: "Restart All", systemImage: "arrow.clockwise", kind: .secondary) {
                services.restartAll(); overlay.toast("Restarting all services")
            }
            KTButton(title: "Start All", kind: .primary) {
                services.startAll(); overlay.toast("Starting all services")
            }
        }
    }

    @ViewBuilder
    private func standardGroup(_ group: (title: String, kinds: [ServiceKind])) -> some View {
        let rows = services.snapshots.filter { group.kinds.contains($0.kind) }
        if !rows.isEmpty {
            Text(group.title.uppercased())
                .font(KTType.sectionLabel).tracking(KTType.sectionLabelTracking)
                .foregroundStyle(KTColor.muted)
                .padding(.horizontal, 2).padding(.top, 18).padding(.bottom, 8)
            KTListContainer { groupRows(rows) }
        }
    }

    private struct DBEntry: Identifiable {
        let snapshot: ServiceSnapshot
        let installedVersions: [String]
        let activeVersion: String?
        var id: ServiceKind { snapshot.kind }
    }

    // Computed once per render: installedVersions() lists a directory, so gather it here and hand
    // plain values to the Equatable rows instead of re-reading disk inside each row body.
    private var dbEntries: [DBEntry] {
        Self.dbKinds.compactMap { kind in
            guard let snap = services.snapshots.first(where: { $0.kind == kind }) else { return nil }
            let cached = dbVersions[kind]
            return DBEntry(
                snapshot: snap,
                installedVersions: cached?.installed ?? services.installedVersions(kind),
                activeVersion: cached?.active ?? services.activeVersion(kind)
            )
        }
    }

    private func refreshDBVersions() {
        dbVersions = Dictionary(uniqueKeysWithValues: Self.dbKinds.map { kind in
            (kind, (services.installedVersions(kind), services.activeVersion(kind)))
        })
    }

    @ViewBuilder
    private var dbGroup: some View {
        let entries = dbEntries
        if !entries.isEmpty {
            Text("DATABASES & CACHE")
                .font(KTType.sectionLabel).tracking(KTType.sectionLabelTracking)
                .foregroundStyle(KTColor.muted)
                .padding(.horizontal, 2).padding(.top, 18).padding(.bottom, 8)
            KTListContainer {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        let kind = entry.snapshot.kind
                        KTDatabaseServiceRow(
                            snapshot: entry.snapshot,
                            installedVersions: entry.installedVersions,
                            activeVersion: entry.activeVersion,
                            onToggle: { services.toggle(kind) },
                            onRestart: { services.restart(kind) },
                            onOpenLogs: { onOpenLogs(Self.logSourceID(for: kind)) },
                            onSetActive: { handleSetActive(kind: kind, version: $0) },
                            onManageInRuntimes: { onNavigate(.runtimes) }
                        )
                        .equatable()
                        if index < entries.count - 1 {
                            Rectangle().fill(KTColor.sepFaint).frame(height: 0.5).padding(.leading, 18)
                        }
                    }
                }
            }
        }
    }

    private func handleSetActive(kind: ServiceKind, version: String) {
        do {
            try services.setActiveVersion(kind, version: version)
            refreshDBVersions()
        } catch { overlay.toast(error.localizedDescription) }
    }

    private func groupRows(_ rows: [ServiceSnapshot]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, snapshot in
                KTServiceRow(
                    snapshot: snapshot,
                    canToggle: true,
                    onToggle: { services.toggle(snapshot.kind) },
                    onRestart: { services.restart(snapshot.kind) },
                    onOpenLogs: { onOpenLogs(Self.logSourceID(for: snapshot.kind)) },
                    onInstall: { services.install(snapshot.kind) },
                    onCancelInstall: { services.cancelInstall(snapshot.kind) },
                    onResetData: { services.resetData(snapshot.kind) },
                    onEditConfig: snapshot.kind == .nginx ? { editingNginxConf = NginxConfEditToken() } : nil
                )
                .equatable()
                if index < rows.count - 1 {
                    Rectangle().fill(KTColor.sepFaint).frame(height: 0.5).padding(.leading, 18)
                }
            }
        }
    }

    private var banners: [ServiceBanner] {
        ServicesBannerBuilder.banners(
            snapshots: services.snapshots, dns: dns, caTrusted: caTrusted, caExists: caExists,
            onEnableDNS: { dns.enable() }, onResetDNS: { dns.reset() },
            onOpenTLSSettings: { onNavigate(.settings) }, onRestart: { services.restart($0) }
        )
    }

    private static func logSourceID(for kind: ServiceKind) -> String? {
        switch kind {
        case .nginx: "nginx-error"
        case .mysql: "mysql"
        case .postgres: "postgres"
        case .redis: "redis"
        case .mongodb: "mongodb"
        case .mailpit: "mailpit"
        case .phpFpm, .dnsmasq: nil
        }
    }
}
