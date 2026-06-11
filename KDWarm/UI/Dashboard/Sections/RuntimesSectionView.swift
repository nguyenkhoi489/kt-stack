import SwiftUI
import KDWarmKit

/// Runtimes dashboard (design wireframe `dashboard-runtimes`): a Bento grid of per-language cards
/// (installed versions, Set default, inline install/progress) + an "Install Version…" sheet. Binds
/// to `RuntimeManager` so installed/download state refreshes live.
struct RuntimesSectionView: View {
    @EnvironmentObject private var runtimes: RuntimeManager
    @State private var showInstall = false

    private let columns = [GridItem(.flexible(), spacing: KDSpacing.space3),
                           GridItem(.flexible(), spacing: KDSpacing.space3)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: KDSpacing.space3) {
                    ForEach(RuntimeLanguage.allCases) { lang in card(lang) }
                }
                .padding(KDSpacing.space3)
            }
        }
        .navigationTitle("Runtimes")
        .sheet(isPresented: $showInstall) { RuntimeDownloadSheet() }
    }

    private var toolbar: some View {
        HStack {
            Text("Languages & versions").font(KDFont.footnote).foregroundStyle(.secondary)
            Spacer()
            Button { showInstall = true } label: { Label("Install Version…", systemImage: "arrow.down.circle") }
        }
        .padding(KDSpacing.space3)
    }

    private func card(_ lang: RuntimeLanguage) -> some View {
        RuntimeCardView(
            language: lang,
            installed: runtimes.installed[lang] ?? [],
            available: runtimes.availableReleases(lang),
            defaultVersion: runtimes.defaultVersion(lang),
            download: runtimes.downloads[lang],
            onSetDefault: { runtimes.setGlobalDefault(lang, $0) },
            onInstall: { runtimes.install($0) },
            onCancel: { runtimes.cancel(lang) })
    }
}
