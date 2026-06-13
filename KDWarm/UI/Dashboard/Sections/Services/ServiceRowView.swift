import SwiftUI
import KDWarmKit

/// One service row in the Services list (design §5.5): SF Symbol · name · secondary detail ·
/// status pill · toggle (or spinner mid-transition, §5.3) · overflow menu (Restart, Logs).
/// A not-installed service shows a neutral pill + a disabled toggle; the section banner explains why.
struct ServiceRowView: View {
    let snapshot: ServiceSnapshot
    /// php-fpm follows the web server (pools auto-reconcile to site needs) → its toggle is read-only.
    let canToggle: Bool
    let onToggle: () -> Void
    let onRestart: () -> Void
    let onOpenLogs: () -> Void
    var onInstall: () -> Void = {}
    var onCancelInstall: () -> Void = {}
    /// Destroy the service's on-disk data (unclean-shutdown recovery). Only surfaced for engines that
    /// can wedge on a stale lock (MongoDB today).
    var onResetData: () -> Void = {}

    @State private var showResetConfirm = false

    /// A crash-looping datastore that a data reset can recover (stale lock after unclean shutdown).
    private var canResetData: Bool { snapshot.kind == .mongodb && snapshot.status == .error }

    var body: some View {
        HStack(spacing: KDSpacing.space2) {
            Image(systemName: snapshot.symbolName)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.displayName).font(KDFont.body)
                Text(secondaryText)
                    .font(KDFont.footnote)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            StatusPill(snapshot.status, text: pillText)

            trailingControl

            overflowMenu
        }
        .padding(.vertical, KDSpacing.space1)
        .padding(.horizontal, KDSpacing.space2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.displayName), \(snapshot.status.label), \(pillText)")
        .confirmationDialog("Reset \(snapshot.displayName) data?", isPresented: $showResetConfirm) {
            Button("Reset \(snapshot.displayName) data", role: .destructive, action: onResetData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \(snapshot.displayName)'s stored data, then restarts it from "
                + "an empty datastore. Use this only to recover a service stuck after an unclean shutdown.")
        }
    }

    /// Right-edge control: download progress, an Install button (on-demand engine), a transition
    /// spinner, or the on/off toggle.
    @ViewBuilder
    private var trailingControl: some View {
        if let fraction = snapshot.downloadFraction {
            HStack(spacing: KDSpacing.space1) {
                ProgressView(value: fraction).frame(width: 56)
                Button { onCancelInstall() } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
            }
        } else if !snapshot.isInstalled && snapshot.installable {
            Button("Install", action: onInstall).controlSize(.small)
        } else if snapshot.isBusy {
            ProgressView().controlSize(.small).frame(width: 32)
        } else {
            Toggle("", isOn: toggleBinding)
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .disabled(!canToggle || !snapshot.isInstalled)
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(get: { snapshot.status == .running }, set: { _ in onToggle() })
    }

    private var pillText: String {
        snapshot.isInstalled ? (snapshot.detail.isEmpty ? snapshot.status.label : snapshot.detail)
                             : "Not installed"
    }

    private var secondaryText: String {
        if !snapshot.isInstalled {
            return snapshot.installable ? "Not installed — click Install to download" : "Not available in this build yet"
        }
        if let error = snapshot.errorMessage { return error }
        return snapshot.kind.subtitle
    }

    private var overflowMenu: some View {
        Menu {
            Button("Restart", systemImage: "arrow.clockwise", action: onRestart)
                .disabled(!canToggle || !snapshot.isInstalled || snapshot.status != .running)
            Button("Open Logs", systemImage: "text.alignleft", action: onOpenLogs)
                .disabled(snapshot.kind == .dnsmasq)
            if canResetData {
                Divider()
                Button("Reset Data…", systemImage: "trash", role: .destructive) { showResetConfirm = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 28)
    }
}

private extension ServiceKind {
    /// Short, stable secondary line under the service name.
    var subtitle: String {
        switch self {
        case .nginx:    return "Reverse proxy · HTTP/HTTPS"
        case .phpFpm:   return "FastCGI pools (managed with web server)"
        case .dnsmasq:  return "*.test resolver (via helper)"
        case .mysql:    return "Database · 127.0.0.1"
        case .postgres: return "Database · 127.0.0.1"
        case .redis:    return "Cache · 127.0.0.1"
        case .mongodb:  return "Document DB · 127.0.0.1"
        case .mailpit:  return "Mail catcher · SMTP :1025"
        }
    }
}
