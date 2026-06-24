import SwiftUI
import KTStackKit

struct KTSiteGridCard: View {
    let site: Site
    let availableVersions: [String]
    let canOpen: Bool
    let isSharing: Bool
    var shareStarting: Bool = false
    var shareURL: URL? = nil
    let onOpen: () -> Void
    let onSetVersion: (String) -> Void
    let onSetSecure: (Bool) -> Void
    let onOpenLogs: () -> Void
    let onToggleShare: (Bool) -> Void
    let onRemove: () -> Void
    var onError: (String) -> Void = { _ in }
    var onRestore: () -> Void = {}

    @State private var phpFramework: PHPFramework = .plain

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                KTIconTile(tint: KTSiteVisuals.tint(for: site.type), size: 42, radius: KTRadius.iconTile) {
                    KTSiteGlyph(kind: KTSiteVisuals.kind(for: site.type), size: 21,
                                color: KTSiteVisuals.tint(for: site.type).fg)
                }
                Spacer()
                KTToggle(isOn: site.secure, action: { onSetSecure(!site.secure) })
                    .help("Serve over HTTPS")
            }
            Text(site.name).font(KTType.cardName).foregroundStyle(KTColor.ink).lineLimit(1)
                .padding(.top, 13)
            Text(site.domain).font(KTType.sub).foregroundStyle(KTColor.muted).lineLimit(1)

            HStack(spacing: 7) {
                KTStatusLabel(running: canOpen)
                Spacer()
                if site.type == .php {
                    KTBadge(text: phpFramework.label, tint: KTSiteVisuals.tint(for: phpFramework), radius: 7)
                    KTPhpMenu(current: site.phpVersion, versions: availableVersions, onSelect: onSetVersion)
                } else {
                    KTBadge(text: site.type.label, tint: KTSiteVisuals.tint(for: site.type), radius: 7)
                }
            }
            .padding(.top, 13)

            HStack(spacing: 8) {
                KTButton(title: "Open", kind: .secondary, action: onOpen)
                    .disabled(!canOpen)
                    .frame(maxWidth: .infinity)
                KTSiteShareControls(shareStarting: shareStarting, shareURL: shareURL, onToggleShare: onToggleShare)
                KTSiteActionsMenu(site: site, canOpen: canOpen,
                                  onOpenLogs: onOpenLogs, onRemove: onRemove,
                                  onRestore: onRestore, onError: onError)
            }
            .padding(.top, 14)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: KTRadius.cardLarge, style: .continuous)
                .fill(.white)
                .overlay(RoundedRectangle(cornerRadius: KTRadius.cardLarge, style: .continuous)
                    .strokeBorder(KTColor.sep, lineWidth: 1))
        )
        .compositingGroup()
        .task(id: site.path) { await detectFramework() }
    }

    private func detectFramework() async {
        guard site.type == .php else { return }
        phpFramework = await PHPFrameworkCache.shared.framework(path: site.path, docroot: site.docroot)
    }
}
