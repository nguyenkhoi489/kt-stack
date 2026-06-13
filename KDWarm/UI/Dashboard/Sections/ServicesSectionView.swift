import SwiftUI
import KDWarmKit

/// Services dashboard (design §5.5, wireframe `dashboard-services`): a live list of all seven
/// services with status pills + per-service toggle/restart, a Start all / Stop all toolbar, and the
/// consolidated error/remediation banners. Binds to the `ServiceManager` health poll so status
/// refreshes sub-second without manual refresh.
struct ServicesSectionView: View {
    /// Lets a banner CTA jump to another dashboard section (e.g. CA-untrusted → Settings).
    var onNavigate: (SidebarItem) -> Void = { _ in }
    /// Opens the Logs view, optionally preselecting this service's log source.
    var onOpenLogs: (String?) -> Void = { _ in }

    @EnvironmentObject private var services: ServiceManager
    @EnvironmentObject private var dns: DNSAutomationService

    private let paths = AppSupportPaths()

    // Cached CA-trust state. Computing it spawns `/usr/bin/security` (reads the whole System keychain),
    // so it must NEVER run inline in `body` — it would fork a subprocess on the main thread on every
    // render and make the tab stutter. Refreshed off-main on a slow loop while the view is visible.
    @State private var caExists = false
    @State private var caTrusted = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !banners.isEmpty {
                        VStack(spacing: KDSpacing.space2) {
                            ForEach(banners) { banner in
                                ServiceErrorBanner(status: banner.status, title: banner.title,
                                                   message: banner.message, ctaTitle: banner.ctaTitle,
                                                   action: banner.action)
                            }
                        }
                        .padding(KDSpacing.space2)
                    }
                    ForEach(services.snapshots) { snapshot in
                        ServiceRowView(
                            snapshot: snapshot,
                            canToggle: snapshot.kind != .phpFpm,
                            onToggle: { services.toggle(snapshot.kind) },
                            onRestart: { services.restart(snapshot.kind) },
                            onOpenLogs: { onOpenLogs(Self.logSourceID(for: snapshot.kind)) },
                            onInstall: { services.install(snapshot.kind) },
                            onCancelInstall: { services.cancelInstall(snapshot.kind) },
                            onResetData: { services.resetData(snapshot.kind) })
                        Divider()
                    }
                }
            }
        }
        .navigationTitle("Services")
        .task { await refreshCATrustLoop() }
    }

    /// Recompute CA-trust off the main thread on a slow cadence while the view is on screen. The
    /// `.task` is cancelled when the view disappears, so there's no background keychain polling when
    /// the user is on another tab.
    private func refreshCATrustLoop() async {
        let caCert = paths.caRootCert
        while !Task.isCancelled {
            let exists = FileManager.default.fileExists(atPath: caCert.path)
            var trusted = false
            if exists {
                trusted = await Task.detached {
                    CATrustService.isTrustedInSystemKeychain(caCert: caCert)
                }.value
            }
            if exists != caExists { caExists = exists }
            if trusted != caTrusted { caTrusted = trusted }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private var toolbar: some View {
        HStack(spacing: KDSpacing.space2) {
            Button("Start All", systemImage: "play.fill") { services.startAll() }
            Button("Stop All", systemImage: "stop.fill") { services.stopAll() }
            Spacer()
            Text("\(runningCount) of \(services.snapshots.count) running")
                .font(KDFont.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(KDSpacing.space2)
    }

    private var runningCount: Int {
        services.snapshots.filter { $0.status == .running }.count
    }

    /// Map a service to its primary log source id (nil = open Logs without a preselection).
    private static func logSourceID(for kind: ServiceKind) -> String? {
        switch kind {
        case .nginx:    return "nginx-error"
        case .mysql:    return "mysql"
        case .postgres: return "postgres"
        case .redis:    return "redis"
        case .mongodb:  return "mongodb"
        case .mailpit:  return "mailpit"
        case .phpFpm, .dnsmasq: return nil
        }
    }

    private var banners: [ServiceBanner] {
        ServicesBannerBuilder.banners(
            snapshots: services.snapshots,
            dns: dns,
            caTrusted: caTrusted,
            caExists: caExists,
            onEnableDNS: { dns.enable() },
            onResetDNS: { dns.reset() },
            onOpenTLSSettings: { onNavigate(.settings) },
            onRestart: { services.restart($0) })
    }
}
