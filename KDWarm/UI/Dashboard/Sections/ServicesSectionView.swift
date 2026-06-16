import SwiftUI
import KDWarmKit

struct ServicesSectionView: View {

    var onNavigate: (SidebarItem) -> Void = { _ in }

    var onOpenLogs: (String?) -> Void = { _ in }

    @EnvironmentObject private var services: ServiceManager
    @EnvironmentObject private var dns: DNSAutomationService

    private let paths = AppSupportPaths()

    
    @State private var caExists = false
    @State private var caTrusted = false

    private static let groups: [(title: String, kinds: [ServiceKind])] = [
        ("Core Proxy & DNS", [.nginx, .dnsmasq]),
        ("Runtimes", [.phpFpm]),
        ("Databases & Cache", [.mysql, .postgres, .redis, .mongodb, .mailpit]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !banners.isEmpty {
                        VStack(spacing: KDSpacing.space2) {
                            ForEach(banners) { banner in
                                ServiceErrorBanner(status: banner.status, title: banner.title,
                                                   message: banner.message, ctaTitle: banner.ctaTitle,
                                                   action: banner.action)
                            }
                        }
                        .padding(.bottom, KDSpacing.space2)
                    }
                    ForEach(Self.groups, id: \.title) { group in
                        let rows = services.snapshots.filter { group.kinds.contains($0.kind) }
                        if !rows.isEmpty {
                            groupHeader(group.title)
                            groupCard(rows)
                        }
                    }
                }
                .padding(KDSpacing.space4)
            }
        }
        .navigationTitle("Services")
        .task { await refreshCATrustLoop() }
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .padding(.top, KDSpacing.space4)
            .padding(.bottom, KDSpacing.space2)
    }

    private func groupCard(_ rows: [ServiceSnapshot]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, snapshot in
                serviceRow(snapshot)
                if index < rows.count - 1 { Divider() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: KDRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: KDRadius.card)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private func serviceRow(_ snapshot: ServiceSnapshot) -> some View {
        ServiceRowView(
            snapshot: snapshot,
            canToggle: snapshot.kind != .phpFpm,
            onToggle: { services.toggle(snapshot.kind) },
            onRestart: { services.restart(snapshot.kind) },
            onOpenLogs: { onOpenLogs(Self.logSourceID(for: snapshot.kind)) },
            onInstall: { services.install(snapshot.kind) },
            onCancelInstall: { services.cancelInstall(snapshot.kind) },
            onResetData: { services.resetData(snapshot.kind) })
    }


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

    private var header: some View {
        HStack(spacing: KDSpacing.space2) {
            Text("Services").font(.largeTitle.weight(.bold))
            Spacer()
            Button("Restart All", systemImage: "arrow.clockwise") { services.restartAll() }
                .buttonStyle(.bordered)
            Button("Stop All", systemImage: "stop.fill") { services.stopAll() }
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .padding(.horizontal, KDSpacing.space4)
        .padding(.vertical, KDSpacing.space3)
    }


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
