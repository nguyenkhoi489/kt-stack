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

    @State private var hovering = false

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
                                  onOpenLogs: onOpenLogs, onRemove: onRemove, onError: onError)
            }
            .padding(.top, 14)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: KTRadius.cardLarge, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: KTRadius.cardLarge, style: .continuous).strokeBorder(KTColor.sep, lineWidth: 0.5))
        .shadow(color: hovering ? .black.opacity(0.16) : .clear, radius: 9, y: 4)
        .onHover { hovering = $0 }
    }
}
