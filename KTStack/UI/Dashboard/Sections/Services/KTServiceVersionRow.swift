import KTStackKit
import SwiftUI

enum KTServiceVersionState {
    case active, installed, available
}

struct KTServiceVersionRow: View {
    let kind: ServiceKind
    let version: String
    let state: KTServiceVersionState
    let isEngineRunning: Bool
    let isRunning: Bool
    let isBusy: Bool
    let downloadFraction: Double?
    let isSwitchOrInstallInFlight: Bool
    let onSetActive: () -> Void
    let onToggleRunning: () -> Void
    let onInstall: () -> Void
    let onCancel: () -> Void
    let onUninstall: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            KTIconTile(tint: KTServiceVisuals.tint(kind), size: 44, radius: 11) {
                Image(systemName: kind.symbolName).font(.system(size: 20, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Text(rowLabel).font(KTType.cardName).foregroundStyle(KTColor.ink)
                    KTBadge(text: badgeText, tint: badgeTint, radius: 20)
                }
                Text(rowNote).font(KTType.sub).foregroundStyle(KTColor.muted)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(hovering ? KTColor.rowHover : Color.clear)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var trailing: some View {
        if let fraction = downloadFraction {
            HStack(spacing: 8) {
                ProgressView(value: fraction).frame(width: 80)
                Button { onCancel() } label: {
                    Image(systemName: "xmark.circle").foregroundStyle(KTColor.muted)
                }
                .buttonStyle(.plain)
            }
        } else {
            switch state {
            case .active:
                if isBusy {
                    ProgressView().controlSize(.small).frame(width: 40)
                } else {
                    HStack(spacing: 12) {
                        Text(isRunning ? "Running" : "Stopped")
                            .font(.jbMono(13, .regular))
                            .foregroundStyle(isRunning ? KTColor.online : KTColor.muted)
                        KTToggle(isOn: isRunning, action: onToggleRunning)
                    }
                }
            case .installed:
                KTButton(title: "Set Active", kind: .secondary, action: onSetActive)
                    .disabled(isEngineRunning || isSwitchOrInstallInFlight)
                    .help(setActiveHelp)
                overflowMenu
            case .available:
                KTButton(title: "Install", kind: .primary, action: onInstall)
                    .disabled(isSwitchOrInstallInFlight)
            }
        }
    }

    @ViewBuilder
    private var overflowMenu: some View {
        Menu {
            Button("Uninstall…", systemImage: "trash", role: .destructive, action: onUninstall)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .regular))
                .foregroundStyle(KTColor.muted).frame(width: 28, height: 30).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
        .disabled(isEngineRunning || isSwitchOrInstallInFlight)
        .help(overflowHelp)
    }

    private var setActiveHelp: String {
        if isEngineRunning { return "Stop \(kind.displayName) before switching versions." }
        if isSwitchOrInstallInFlight { return "An operation is in progress." }
        return ""
    }

    private var overflowHelp: String {
        if isEngineRunning { return "Stop \(kind.displayName) before uninstalling." }
        if isSwitchOrInstallInFlight { return "An operation is in progress." }
        return ""
    }

    private var rowLabel: String {
        "\(kind.displayName) \(version)"
    }

    private var badgeText: String {
        switch state {
        case .active: "Active"
        case .installed: "Installed"
        case .available: "Available"
        }
    }

    private var badgeTint: KTTint {
        switch state {
        case .active: KTTint(fg: KTColor.online, bg: KTColor.onlineBg)
        case .installed: KTTint(fg: KTColor.ink3, bg: KTColor.pillBg)
        case .available: KTTint(fg: KTColor.accent, bg: Color(hex: 0xEAF1FF))
        }
    }

    private var rowNote: String {
        switch state {
        case .active: isRunning ? "Running from \(kind.rawValue)/\(version)." : "Active version. Stopped."
        case .installed: "Installed, not active."
        case .available: "Not installed. Download to use."
        }
    }
}
