import KTStackKit
import SwiftUI

enum KTRuntimeState {
    case active, installed, available
}

struct KTRuntimeRow: View {
    let language: RuntimeLanguage
    let version: String
    let state: KTRuntimeState
    let downloadFraction: Double?
    let onSetDefault: () -> Void
    let onInstall: () -> Void
    let onCancel: () -> Void
    let onUninstall: () -> Void
    var onEditIni: (() -> Void)?
    var onManageExtensions: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            KTIconTile(tint: KTIconTint.cube, size: 44, radius: 11) {
                Image(systemName: language.symbolName).font(.system(size: 20, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 9) {
                    Text(label).font(KTType.cardName).foregroundStyle(KTColor.ink)
                    KTBadge(text: badgeText, tint: badgeTint, radius: 20)
                    if isEndOfLife {
                        KTBadge(text: "EOL", tint: KTTint(fg: KTColor.danger, bg: KTColor.dangerBg), radius: 20)
                    }
                }
                Text(note).font(KTType.sub).foregroundStyle(KTColor.muted)
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
                Button { onCancel() } label: { Image(systemName: "xmark.circle").foregroundStyle(KTColor.muted) }
                    .buttonStyle(.plain)
            }
        } else {
            switch state {
            case .active:
                Text("Default")
                    .font(.jbMono(13, .regular)).foregroundStyle(KTColor.online)
                    .padding(.vertical, 8).padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KTColor.onlineBg))
                phpMenu
            case .installed:
                KTButton(title: "Set Default", kind: .secondary, action: onSetDefault)
                phpMenu
            case .available:
                KTButton(title: "Install", kind: .primary, action: onInstall)
            }
        }
    }

    @ViewBuilder
    private var phpMenu: some View {
        if onEditIni != nil || onManageExtensions != nil || state != .available {
            Menu {
                if let onEditIni { Button("Edit php.ini…", systemImage: "doc.text", action: onEditIni) }
                if let onManageExtensions { Button("Manage Extensions…", systemImage: "puzzlepiece.extension", action: onManageExtensions) }
                Divider()
                Button("Uninstall…", systemImage: "trash", role: .destructive, action: onUninstall)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .regular))
                    .foregroundStyle(KTColor.muted).frame(width: 28, height: 30).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
        }
    }

    private var isEndOfLife: Bool {
        language == .php && BundledPHP.isEndOfLife(version)
    }

    private var label: String {
        let prefix = language == .php ? "PHP" : "Node"
        return "\(prefix) \(version)"
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

    private var note: String {
        switch state {
        case .active: language == .php ? "Default for new sites and terminals." : "Installed and ready."
        case .installed: "Installed and ready."
        case .available: "Not installed — download to use."
        }
    }
}
