import SwiftUI
import KDWarmKit

/// One extension row in the manager sheet: status icon · name + type tag + summary · action. Built-ins
/// are status-only ("Built-in"); optional extensions show Install (with progress) / Uninstall, plus a
/// load-failure warning when an installed `.so` did not initialize.
struct PHPExtensionRowView: View {
    let ext: PHPExtension
    let status: PHPExtensionStatus
    let busy: Bool
    let progress: Double?
    let error: String?
    let onInstall: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: KDSpacing.space2) {
                statusIcon.frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(ext.displayName).font(KDFont.headline)
                        typeTag
                    }
                    Text(ext.summary).font(KDFont.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: KDSpacing.space2)
                action
            }
            if busy, let progress { ProgressView(value: progress) }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(Color.KDStatus.error)
                    .lineLimit(3).padding(.leading, 26)
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder private var statusIcon: some View {
        switch status {
        case .builtIn, .installed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.KDStatus.running)
        case .installedButFailedToLoad:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.KDStatus.error)
        case .available:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .unavailable:
            Image(systemName: "minus.circle").foregroundStyle(.tertiary)
        }
    }

    private var typeTag: some View {
        Text(ext.type.rawValue)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var action: some View {
        if busy {
            Text(status == .installed || status == .installedButFailedToLoad ? "Removing…" : "Installing…")
                .font(KDFont.footnote).foregroundStyle(.secondary)
        } else {
            switch status {
            case .builtIn:
                Text("Built-in").font(KDFont.footnote).foregroundStyle(.tertiary)
            case .installed:
                Button("Uninstall", action: onUninstall).buttonStyle(.borderless)
                    .font(KDFont.footnote).foregroundStyle(Color.KDStatus.error)
            case .installedButFailedToLoad:
                HStack(spacing: KDSpacing.space2) {
                    Button("Reinstall", action: onInstall).buttonStyle(.borderless).font(KDFont.footnote)
                    Button("Remove", action: onUninstall).buttonStyle(.borderless)
                        .font(KDFont.footnote).foregroundStyle(Color.KDStatus.error)
                }
            case .available:
                Button("Install", action: onInstall).buttonStyle(.borderless).font(KDFont.footnote)
            case .unavailable:
                Text("n/a").font(KDFont.footnote).foregroundStyle(.tertiary)
                    .help("No \(ext.displayName) build is available for this PHP version.")
            }
        }
    }
}
