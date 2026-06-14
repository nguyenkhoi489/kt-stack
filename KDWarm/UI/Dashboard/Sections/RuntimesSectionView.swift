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
    @State private var managingExt: EditingIni?
    @State private var pendingUninstall: PendingUninstall?
    /// `php -m` per installed PHP version, loaded off-main (the probe runs the binary).
    @State private var phpExtensions: [String: [String]] = [:]

    /// Identifiable wrapper so the editor sheet binds to which PHP version was tapped.
    private struct EditingIni: Identifiable { let version: String; var id: String { version } }

    /// A remove request awaiting confirmation. `inUseBy` lists the site domains still on this version
    /// (PHP only). Removal is ALLOWED even when in use — those sites fall back to another installed PHP
    /// version — but the confirm spells out the consequence.
    private struct PendingUninstall: Identifiable {
        let language: RuntimeLanguage
        let version: String
        let inUseBy: [String]
        var id: String { "\(language.rawValue)-\(version)" }
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
        .sheet(item: $managingExt) { PHPExtensionsSheet(version: $0.version) }
        .alert(item: $pendingUninstall, content: uninstallAlert)
        .task(id: runtimes.installed[.php] ?? []) { await loadPHPExtensions() }
    }

    /// Build a request: note which sites still use this version (PHP) so the confirm can warn.
    private func requestUninstall(_ lang: RuntimeLanguage, _ version: String) {
        let inUse = lang == .php
            ? server.registry.sites.filter { $0.type == .php && $0.phpVersion == version }.map(\.domain)
            : []
        pendingUninstall = PendingUninstall(language: lang, version: version, inUseBy: inUse)
    }

    private func uninstallAlert(_ p: PendingUninstall) -> Alert {
        let name = "\(p.language.displayName) \(p.version)"
        guard !p.inUseBy.isEmpty else {
            return Alert(title: Text("Remove \(name)?"),
                         message: Text("This deletes the downloaded runtime. You can reinstall it anytime from here."),
                         primaryButton: .destructive(Text("Remove")) { performUninstall(p) },
                         secondaryButton: .cancel())
        }
        let n = p.inUseBy.count
        let sites = p.inUseBy.joined(separator: ", ")
        let others = (runtimes.installed[.php] ?? []).filter { $0 != p.version }
        let consequence = others.isEmpty
            ? "No other PHP is installed, so those sites will stop serving until you install one."
            : "Those sites will fall back to PHP \(others.max { $0.compare($1, options: .numeric) == .orderedAscending }!) until you switch them."
        return Alert(
            title: Text("Remove \(name)?"),
            message: Text("In use by \(n) site\(n == 1 ? "" : "s"): \(sites). \(consequence)"),
            primaryButton: .destructive(Text("Remove anyway")) { performUninstall(p) },
            secondaryButton: .cancel())
    }

    /// Remove the runtime, then re-apply web config so PHP sites that used it re-route to their
    /// fallback version (no lingering 502 against a now-deleted pool socket).
    private func performUninstall(_ p: PendingUninstall) {
        runtimes.uninstall(p.language, p.version)
        if p.language == .php { server.reconcileAfterRuntimeChange() }
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
            onManageExtensions: lang == .php ? { managingExt = EditingIni(version: $0) } : nil,
            extensions: lang == .php ? phpExtensions : [:])
    }
}
