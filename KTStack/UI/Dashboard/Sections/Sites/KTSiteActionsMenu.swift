import SwiftUI
import KTStackKit

struct KTSiteActionsMenu: View {
    let site: Site
    let canOpen: Bool
    let onOpenLogs: () -> Void
    let onRemove: () -> Void
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
            VStack(alignment: .leading, spacing: 1) {
                row("Open in Browser", "safari", "⌘O", enabled: canOpen) { KTSiteActions.openInBrowser(site) }
                row("Reveal in Finder", "folder", "⇧⌘R") { KTSiteActions.revealInFinder(site) }
                row("Open Terminal Here", "terminal", "⌥⌘T") { KTSiteActions.openTerminal(site) }
                divider
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
                }
                divider
                row("Remove Site", "trash", "⌘⌫", danger: true, action: onRemove)
            }
            .padding(6)
            .frame(width: 252)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color(hex: 0xE8E8EE)).frame(height: 0.5).padding(.horizontal, 8).padding(.vertical, 4)
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
