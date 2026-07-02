import KTStackKit
import SwiftUI

// DB and cache engines are on-demand runtimes like PHP/Node, so their install/switch/run UI lives
// with the runtimes rather than under Services. Backed by ServiceManager (ServiceKind), not
// RuntimeManager, because they are supervised services once running.
struct KTDatabaseEnginesSection: View {
    @EnvironmentObject private var services: ServiceManager
    @EnvironmentObject private var overlay: KTOverlayCenter

    private static let kinds: [ServiceKind] = [.mysql, .postgres, .redis, .mongodb]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DATABASES & CACHE")
                .font(KTType.sectionLabel).tracking(KTType.sectionLabelTracking).foregroundStyle(KTColor.faint)
                .padding(.leading, 4)
            Text("Install and run bundled engines. Data is stored separately per version.")
                .font(KTType.sub).foregroundStyle(KTColor.muted).padding(.leading, 4)
            KTListContainer { rows }
        }
    }

    private var rows: some View {
        let items = entries
        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                let kind = entry.kind
                let snap = services.snapshots.first(where: { $0.kind == kind })
                let isEngineActive = snap?.status == .running || snap?.isBusy == true
                KTServiceVersionRow(
                    kind: kind,
                    version: entry.version,
                    state: entry.state,
                    isEngineRunning: isEngineActive,
                    isRunning: snap?.status == .running,
                    isBusy: snap?.isBusy ?? false,
                    downloadFraction: entry.release.flatMap { services.installProgress(for: $0) },
                    isSwitchOrInstallInFlight: services.isInstallInFlight(kind),
                    onSetActive: { handleSetActive(kind: kind, version: entry.version) },
                    onToggleRunning: { services.toggle(kind) },
                    onInstall: { if let r = entry.release { services.install(r) } },
                    onCancel: { if let r = entry.release { services.cancelInstall(r) } },
                    onUninstall: { handleUninstall(kind: kind, version: entry.version) }
                )
                if index < items.count - 1 {
                    Rectangle().fill(KTColor.sepFaint).frame(height: 0.5).padding(.leading, 18)
                }
            }
        }
    }

    private struct Entry: Identifiable {
        var id: String
        var kind: ServiceKind
        var version: String
        var state: KTServiceVersionState
        var release: ServiceBinaryRelease?
    }

    private var entries: [Entry] {
        var result: [Entry] = []
        for kind in Self.kinds {
            let active = services.activeVersion(kind)
            for version in services.installedVersions(kind) {
                result.append(Entry(
                    id: "\(kind.rawValue)-\(version)",
                    kind: kind,
                    version: version,
                    state: version == active ? .active : .installed,
                    release: nil
                ))
            }
            for release in services.availableReleases(kind) {
                result.append(Entry(
                    id: release.id,
                    kind: kind,
                    version: release.version,
                    state: .available,
                    release: release
                ))
            }
        }
        return result
    }

    private func handleSetActive(kind: ServiceKind, version: String) {
        do { try services.setActiveVersion(kind, version: version) }
        catch { overlay.toast(error.localizedDescription) }
    }

    private func handleUninstall(kind: ServiceKind, version: String) {
        do { try services.uninstall(kind: kind, version: version) }
        catch { overlay.toast(error.localizedDescription) }
    }
}
