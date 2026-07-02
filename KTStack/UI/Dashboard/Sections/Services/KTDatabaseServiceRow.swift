import KTStackKit
import SwiftUI

// Compact Services-tab row for a bundled DB/cache engine: run/stop + swap among installed versions.
// Version download/uninstall stays on the Runtimes screen (KTDatabaseEnginesSection).
struct KTDatabaseServiceRow: View, Equatable {
    let snapshot: ServiceSnapshot
    let installedVersions: [String]
    let activeVersion: String?
    let onToggle: () -> Void
    let onRestart: () -> Void
    let onOpenLogs: () -> Void
    let onSetActive: (String) -> Void
    let onManageInRuntimes: () -> Void

    @State private var hovering = false

    // Skip re-render on cpu/mem-only changes (sampled ~0.9s) so the metric tick doesn't stutter the
    // toggle mid-flip. Live metrics update via the isolated DBRowMetricsText subview.
    static func == (a: KTDatabaseServiceRow, b: KTDatabaseServiceRow) -> Bool {
        a.snapshot.kind == b.snapshot.kind
            && a.snapshot.status == b.snapshot.status
            && a.snapshot.detail == b.snapshot.detail
            && a.snapshot.isInstalled == b.snapshot.isInstalled
            && a.snapshot.isBusy == b.snapshot.isBusy
            && a.snapshot.errorMessage == b.snapshot.errorMessage
            && a.activeVersion == b.activeVersion
            && a.installedVersions == b.installedVersions
    }

    private var kind: ServiceKind { snapshot.kind }
    private var isRunning: Bool { snapshot.status == .running }

    var body: some View {
        HStack(spacing: 14) {
            KTIconTile(tint: KTServiceVisuals.tint(kind), size: 40, radius: 11) {
                Image(systemName: snapshot.symbolName).font(.system(size: 18, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayName).font(KTType.rowName).foregroundStyle(KTColor.ink)
                Text(secondaryText).font(KTType.sub).foregroundStyle(KTColor.muted).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if snapshot.isInstalled {
                versionDropdown
                DBRowMetricsText(kind: kind)
                statusLabel.frame(width: 104, alignment: .leading)
                restartButton
                trailingControl
                overflowMenu
            } else {
                KTButton(title: "Runtimes", kind: .secondary, action: onManageInRuntimes)
            }
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 18)
        .background(hovering ? KTColor.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var versionDropdown: some View {
        // KTDropdown holds versions only (no divider / action items); switching is blocked while the
        // engine runs because ServiceManager.setActiveVersion refuses a version change on a live engine.
        KTDropdown(
            width: 150,
            options: installedVersions.map { version in
                KTDropdownOption(label: version, active: version == activeVersion) { onSetActive(version) }
            }
        ) {
            KTDropdownChevronLabel(text: activeVersion ?? "—")
        }
        .fixedSize()
        .disabled(isRunning || snapshot.isBusy || installedVersions.isEmpty)
        .opacity(isRunning || snapshot.isBusy ? 0.5 : 1)
        .help(isRunning ? "Stop \(kind.displayName) to switch version" : "")
    }

    @ViewBuilder
    private var trailingControl: some View {
        if snapshot.isBusy {
            ProgressView().controlSize(.small).frame(width: 40)
        } else {
            KTToggle(isOn: isRunning, action: onToggle)
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
            Button("Manage in Runtimes…", systemImage: "cube", action: onManageInRuntimes)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 15, weight: .regular))
                .foregroundStyle(KTColor.muted).frame(width: 28, height: 30).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
    }

    private var canRestart: Bool {
        snapshot.isInstalled && isRunning && !snapshot.isBusy
    }

    private var statusLabel: some View {
        HStack(spacing: 7) {
            KTDot(color: dotColor)
            Text(pillText).font(.jbMono(13, .medium)).foregroundStyle(textColor)
        }
    }

    private var pillText: String {
        snapshot.status == .warning ? "Degraded" : snapshot.status.label
    }

    private var secondaryText: String {
        if !snapshot.isInstalled { return "Not installed — install in Runtimes" }
        if let error = snapshot.errorMessage { return error }
        return KTServiceVisuals.subtitle(kind)
    }

    private var dotColor: Color {
        switch snapshot.status {
        case .running: KTColor.runDot
        case .error: KTColor.danger
        case .warning: Color(hex: 0xFF9F0A)
        case .starting: KTColor.accent
        default: KTColor.stopDot
        }
    }

    private var textColor: Color {
        switch snapshot.status {
        case .running: KTColor.ink
        case .error: KTColor.danger
        case .warning: Color(hex: 0xFF9F0A)
        default: KTColor.stopText
        }
    }
}

// Observes ServiceManager on its own so the ~0.9s cpu/mem refresh re-renders just this text, not the
// parent row (Equatable skips metric-only changes, keeping the toggle smooth).
private struct DBRowMetricsText: View {
    @EnvironmentObject private var services: ServiceManager
    let kind: ServiceKind

    var body: some View {
        if let metrics = services.snapshots.first(where: { $0.kind == kind })?.metricsText {
            Text(metrics).font(.jbMono(12)).monospacedDigit().foregroundStyle(KTColor.muted)
        }
    }
}
