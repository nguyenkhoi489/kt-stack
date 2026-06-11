import SwiftUI
import KDWarmKit

/// One Bento card for a language (design wireframe `dashboard-runtimes`): header with icon + name +
/// bundled/on-demand badge, the installed versions (each with a Global tag / Set-default action),
/// inline determinate download progress, and Install buttons for available releases.
struct RuntimeCardView: View {
    let language: RuntimeLanguage
    let installed: [String]
    let available: [RuntimeRelease]
    let defaultVersion: String?
    let download: RuntimeManager.DownloadState?
    let onSetDefault: (String) -> Void
    let onInstall: (RuntimeRelease) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space2) {
            header
            if installed.isEmpty && download == nil && available.isEmpty {
                Text("No versions available yet.").font(KDFont.footnote).foregroundStyle(.tertiary)
            }
            ForEach(installed, id: \.self) { version in installedRow(version) }
            if let download { downloadRow(download) }
            ForEach(available) { release in availableRow(release) }
        }
        .padding(KDSpacing.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 0.5))
    }

    private var header: some View {
        HStack(spacing: KDSpacing.space2) {
            Image(systemName: language.symbolName)
                .font(.system(size: 18)).frame(width: 26).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(language.displayName).font(KDFont.headline)
                Text(subtitle).font(KDFont.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text(language.isBundled ? "Bundled" : "On-demand")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(language.isBundled
                    ? Color.KDStatus.running.opacity(0.16) : Color.secondary.opacity(0.15)))
                .foregroundStyle(language.isBundled ? Color.KDStatus.running : .secondary)
        }
    }

    private var subtitle: String {
        if download != nil { return "downloading…" }
        let n = installed.count
        return n == 0 ? "not installed" : "\(n) version\(n == 1 ? "" : "s") installed"
    }

    private func installedRow(_ version: String) -> some View {
        HStack(spacing: KDSpacing.space2) {
            Text(version).font(KDFont.mono)
            Spacer()
            if defaultVersion == version {
                Text("Global").font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor)).foregroundStyle(.white)
            } else {
                Button("Set default") { onSetDefault(version) }
                    .buttonStyle(.link).font(KDFont.footnote)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5))
    }

    private func downloadRow(_ state: RuntimeManager.DownloadState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = state.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(KDFont.footnote).foregroundStyle(Color.KDStatus.error)
                    .lineLimit(2)
                Button("Retry") { if let r = available.first(where: { $0.version == state.version }) ?? RuntimeCatalog.manifest.first(where: { $0.language == language && $0.version == state.version }) { onInstall(r) } }
                    .buttonStyle(.link).font(KDFont.footnote)
            } else {
                HStack {
                    Text("Installing \(state.version)…").font(KDFont.footnote)
                    Spacer()
                    Button("Cancel", action: onCancel).buttonStyle(.link).font(KDFont.footnote)
                }
                ProgressView(value: state.fraction)
                Text(progressDetail(state)).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.06)))
    }

    private func availableRow(_ release: RuntimeRelease) -> some View {
        HStack(spacing: KDSpacing.space2) {
            Text(release.version).font(KDFont.mono).foregroundStyle(.secondary)
            Spacer()
            Button("Install") { onInstall(release) }
                .buttonStyle(.borderless).font(KDFont.footnote)
                .disabled(download != nil && download?.error == nil)
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
    }

    private func progressDetail(_ state: RuntimeManager.DownloadState) -> String {
        let f = ByteCountFormatter()
        let got = f.string(fromByteCount: state.received)
        guard state.total > 0 else { return got }
        return "\(Int(state.fraction * 100))% · \(got) / \(f.string(fromByteCount: state.total))"
    }
}
