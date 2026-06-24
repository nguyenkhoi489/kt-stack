import SwiftUI
import KTStackKit

struct KTSiteActionsMenu: View {
    let site: Site
    let canOpen: Bool
    let onOpenLogs: () -> Void
    let onRemove: () -> Void
    var onRestore: () -> Void = {}
    var onError: (String) -> Void = { _ in }

    @EnvironmentObject private var overlay: KTOverlayCenter
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(KTColor.muted)
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More actions for \(site.name)")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                header
                divider
                VStack(alignment: .leading, spacing: 1) {
                    sectionLabel("Open")
                    row("Open in Browser", "safari", "⌘O", enabled: canOpen) { KTSiteActions.openInBrowser(site) }
                    row("Reveal in Finder", "folder", "⇧⌘R") { KTSiteActions.revealInFinder(site) }
                    row("Open Terminal Here", "terminal", "⌥⌘T") { KTSiteActions.openTerminal(site) }
                    sectionLabel("Develop")
                    row("Logs", "text.alignleft", "⌘L", action: onOpenLogs)
                    if site.type == .node {
                        row("Node Logs", "shippingbox", "") { KTSiteActions.openNodeLog(site) }
                    }
                    row("API Tester", "network", "") { overlay.apiTesterSite = site }
                    if site.type == .php {
                        row("Configure VS Code Debug", "curlybraces", "") {
                            do { try KTSiteActions.configureVSCode(site) }
                            catch { onError(error.localizedDescription) }
                        }
                        row("Restore from Backup…", "arrow.uturn.backward.circle", "", action: onRestore)
                    }
                }
                .padding(.horizontal, 6)
                divider
                row("Remove Site", "trash", "⌘⌫", danger: true, action: onRemove)
                    .padding(.horizontal, 6).padding(.bottom, 6)
            }
            .padding(.top, 8)
            .frame(width: 268)
            .background(Color.white)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            KTIconTile(tint: KTSiteVisuals.tint(for: site.type), size: 32) {
                KTSiteGlyph(kind: KTSiteVisuals.kind(for: site.type), size: 16,
                            color: KTSiteVisuals.tint(for: site.type).fg)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(site.name).font(KTType.label).foregroundStyle(KTColor.ink).lineLimit(1)
                Text("\(site.domain) · \(runtimeLabel)")
                    .font(KTType.caption).foregroundStyle(KTColor.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.bottom, 8)
    }

    private var runtimeLabel: String {
        switch site.type {
        case .php:  return "PHP \(site.phpVersion)"
        case .node, .staticSite: return site.type.label
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(KTType.sectionLabel)
            .tracking(KTType.sectionLabelTracking)
            .foregroundStyle(KTColor.faint)
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 3)
    }

    private var divider: some View {
        Rectangle().fill(KTColor.sep).frame(height: 0.5).padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func row(_ title: String, _ symbol: String, _ shortcut: String,
                     enabled: Bool = true, danger: Bool = false,
                     action: @escaping () -> Void) -> some View {
        KTActionRow(title: title, symbol: symbol, shortcut: shortcut, enabled: enabled, danger: danger) {
            open = false
            action()
        }
    }
}

private struct KTActionRow: View {
    let title: String
    let symbol: String
    let shortcut: String
    let enabled: Bool
    let danger: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(danger ? KTColor.danger : KTColor.ink2)
                    .frame(width: 18)
                Text(title)
                    .font(.jbMono(13.5))
                    .foregroundStyle(danger ? KTColor.danger : KTColor.ink)
                Spacer(minLength: 12)
                if !shortcut.isEmpty {
                    Text(shortcut).font(.jbMono(12.5)).foregroundStyle(KTColor.faint)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering && enabled ? (danger ? KTColor.dangerBg : KTColor.accentSoft) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}
