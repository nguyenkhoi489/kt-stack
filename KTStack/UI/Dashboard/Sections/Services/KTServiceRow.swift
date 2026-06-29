import KTStackKit
import SwiftUI

struct KTServiceRow: View {
    let snapshot: ServiceSnapshot
    let canToggle: Bool
    let onToggle: () -> Void
    let onRestart: () -> Void
    let onOpenLogs: () -> Void
    var onInstall: () -> Void = {}
    var onCancelInstall: () -> Void = {}
    var onResetData: () -> Void = {}

    @State private var hovering = false
    @State private var showResetConfirm = false

    var body: some View {
        HStack(spacing: 14) {
            KTIconTile(tint: tint, size: 40, radius: 11) {
                Image(systemName: snapshot.symbolName).font(.system(size: 18, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayName).font(KTType.rowName).foregroundStyle(KTColor.ink)
                Text(secondaryText).font(KTType.sub).foregroundStyle(KTColor.muted).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if let metrics = snapshot.metricsText {
                Text(metrics).font(.jbMono(12)).monospacedDigit().foregroundStyle(KTColor.muted)
            }
            statusLabel.frame(width: 104, alignment: .leading)
            restartButton
            trailingControl
            overflowMenu
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 18)
        .background(hovering ? KTColor.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .confirmationDialog("Reset \(snapshot.displayName) data?", isPresented: $showResetConfirm) {
            Button("Reset \(snapshot.displayName) data", role: .destructive, action: onResetData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \(snapshot.displayName)'s stored data, then restarts it from an empty datastore.")
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 7) {
            KTDot(color: dotColor)
            Text(pillText).font(.jbMono(13, .medium)).foregroundStyle(textColor)
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if let fraction = snapshot.downloadFraction {
            HStack(spacing: 6) {
                ProgressView(value: fraction).frame(width: 56)
                Button { onCancelInstall() } label: { Image(systemName: "xmark.circle").foregroundStyle(KTColor.muted) }
                    .buttonStyle(.plain)
            }
        } else if !snapshot.isInstalled, snapshot.installable {
            KTButton(title: "Install", kind: .primary, action: onInstall)
        } else if snapshot.isBusy {
            ProgressView().controlSize(.small).frame(width: 40)
        } else {
            KTToggle(isOn: snapshot.status == .running, action: onToggle)
                .disabled(!canToggle || !snapshot.isInstalled)
                .opacity(canToggle && snapshot.isInstalled ? 1 : 0.45)
        }
    }

    private var restartButton: some View {
        Button(action: onRestart) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(KTColor.ink3)
                .frame(width: 34, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(KTColor.btnBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!canRestart)
        .opacity(canRestart ? 1 : 0.4)
        .help("Restart \(snapshot.displayName)")
    }

    private var overflowMenu: some View {
        Menu {
            Button("Open Logs", systemImage: "text.alignleft", action: onOpenLogs)
                .disabled(snapshot.kind == .dnsmasq)
            if snapshot.kind == .mongodb, snapshot.status == .error {
                Divider()
                Button("Reset Data…", systemImage: "trash", role: .destructive) { showResetConfirm = true }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .regular))
                .foregroundStyle(KTColor.muted).frame(width: 28, height: 30).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
    }

    private var canRestart: Bool {
        canToggle && snapshot.isInstalled && snapshot.status == .running
    }

    private var pillText: String {
        guard snapshot.isInstalled else { return "Not installed" }
        return snapshot.status == .warning ? "Degraded" : snapshot.status.label
    }

    private var secondaryText: String {
        if !snapshot.isInstalled {
            return snapshot.installable ? "Not installed — click Install to download" : "Not available in this build yet"
        }
        if let error = snapshot.errorMessage { return error }
        return KTServiceVisuals.subtitle(snapshot.kind)
    }

    private var dotColor: Color {
        guard snapshot.isInstalled else { return KTColor.stopDot }
        switch snapshot.status {
        case .running: return KTColor.runDot
        case .error: return KTColor.danger
        case .warning: return Color(hex: 0xFF9F0A)
        case .starting: return KTColor.accent
        default: return KTColor.stopDot
        }
    }

    private var textColor: Color {
        guard snapshot.isInstalled else { return KTColor.stopText }
        switch snapshot.status {
        case .running: return KTColor.ink
        case .error: return KTColor.danger
        case .warning: return Color(hex: 0xFF9F0A)
        default: return KTColor.stopText
        }
    }

    private var tint: KTTint {
        KTServiceVisuals.tint(snapshot.kind)
    }
}
