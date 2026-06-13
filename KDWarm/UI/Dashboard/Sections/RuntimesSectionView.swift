import SwiftUI
import KDWarmKit

/// Runtimes dashboard (design wireframe `dashboard-runtimes`): a Bento grid of per-language cards
/// (installed versions, Set default, inline install/progress) + an "Install Version…" sheet. Binds
/// to `RuntimeManager` so installed/download state refreshes live.
struct RuntimesSectionView: View {
    @EnvironmentObject private var runtimes: RuntimeManager
    /// Read-only here: used to block removing a PHP version that registered sites still reference.
    @EnvironmentObject private var server: LocalServerController
    @State private var showInstall = false
    @State private var editingIni: EditingIni?
    @State private var pendingUninstall: PendingUninstall?
    /// `php -m` per installed PHP version, loaded off-main (the probe runs the binary).
    @State private var phpExtensions: [String: [String]] = [:]

    /// Identifiable wrapper so the editor sheet binds to which PHP version was tapped.
    private struct EditingIni: Identifiable { let version: String; var id: String { version } }

    /// A remove request awaiting confirmation. `blockedBy` lists the site domains still on this
    /// version (PHP only); non-empty means removal is refused, not just confirmed.
    private struct PendingUninstall: Identifiable {
        let language: RuntimeLanguage
        let version: String
        let blockedBy: [String]
        var id: String { "\(language.rawValue)-\(version)" }
        var canRemove: Bool { blockedBy.isEmpty }
    }

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
        .sheet(item: $editingIni) { PHPIniEditorSheet(version: $0.version) }
        .alert(item: $pendingUninstall, content: uninstallAlert)
        .task(id: runtimes.installed[.php] ?? []) { await loadPHPExtensions() }
    }

    /// Build a request: PHP versions still bound to sites are refused; everything else is confirmed.
    private func requestUninstall(_ lang: RuntimeLanguage, _ version: String) {
        let blockers = lang == .php
            ? server.registry.sites.filter { $0.type == .php && $0.phpVersion == version }.map(\.domain)
            : []
        pendingUninstall = PendingUninstall(language: lang, version: version, blockedBy: blockers)
    }

    private func uninstallAlert(_ p: PendingUninstall) -> Alert {
        let name = "\(p.language.displayName) \(p.version)"
        guard p.canRemove else {
            let n = p.blockedBy.count
            return Alert(
                title: Text("Can’t remove \(name)"),
                message: Text("In use by \(n) site\(n == 1 ? "" : "s"): \(p.blockedBy.joined(separator: ", ")). Switch them to another version first."),
                dismissButton: .default(Text("OK")))
        }
        return Alert(
            title: Text("Remove \(name)?"),
            message: Text("This deletes the downloaded runtime. You can reinstall it anytime from here."),
            primaryButton: .destructive(Text("Remove")) { runtimes.uninstall(p.language, p.version) },
            secondaryButton: .cancel())
    }

    /// Probe `php -m` for each installed PHP version off the main thread, then publish the map.
    private func loadPHPExtensions() async {
        let versions = runtimes.installed[.php] ?? []
        let map = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: versions.map { ($0, PHPModules.list(version: $0)) })
        }.value
        phpExtensions = map
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
            onCancel: { runtimes.cancel(lang) },
            onUninstall: { requestUninstall(lang, $0) },
            onEditIni: lang == .php ? { editingIni = EditingIni(version: $0) } : nil,
            extensions: lang == .php ? phpExtensions : [:])
    }
}
