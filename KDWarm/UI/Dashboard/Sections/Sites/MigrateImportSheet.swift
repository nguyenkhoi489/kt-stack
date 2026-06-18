import SwiftUI
import KDWarmKit

@MainActor
final class MigrateImportModel: ObservableObject {
    @Published private(set) var discovered: [DiscoveredSite] = []
    @Published var selected: Set<String> = []
    @Published private(set) var importing = false
    @Published private(set) var log: [String] = []

    func load() {
        discovered = ExternalSiteDiscovery.discoverAll()
        selected = Set(discovered.map(\.id))
    }

    func nearest(_ site: DiscoveredSite, installed: [String]) -> (version: String, exact: Bool)? {
        ProjectVersionResolver.nearest(to: site.phpVersion ?? BundledPHP.defaultVersion, installed: installed)
    }

    func importSelected(registry: SiteRegistry, installed: [String]) {
        guard !importing else { return }
        importing = true
        log = []
        for site in discovered where selected.contains(site.id) {
            do {
                let safe = try ImportSafety.resolvedSafeDocroot(site.path)
                let php = nearest(site, installed: installed)?.version ?? BundledPHP.defaultVersion
                let added = try registry.add(folder: safe, phpVersion: php, respectProjectMarkers: false)
                log.append("✓ \(added.domain) (PHP \(added.phpVersion))")
            } catch {
                log.append("✗ \(site.name): \(error.localizedDescription)")
            }
        }
        importing = false
    }
}

struct MigrateImportSheet: View {
    @ObservedObject var registry: SiteRegistry
    let availableVersions: [String]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MigrateImportModel()

    private var grouped: [String: [DiscoveredSite]] {
        Dictionary(grouping: model.discovered, by: \.tool)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Text("Import Sites").font(KDFont.title)
            if model.discovered.isEmpty {
                Text("No sites found from Valet, Herd, MAMP or Local.")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
            } else {
                ScrollView { list }.frame(maxHeight: 360)
            }
            if !model.log.isEmpty {
                Divider()
                ForEach(model.log, id: \.self) { Text($0).font(KDFont.footnote) }
            }
            controls
        }
        .padding(KDSpacing.space4)
        .frame(width: 560)
        .onAppear { model.load() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            ForEach(grouped.keys.sorted(), id: \.self) { tool in
                VStack(alignment: .leading, spacing: KDSpacing.space1) {
                    Text(tool).font(KDFont.headline)
                    ForEach(grouped[tool] ?? []) { site in row(site) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ site: DiscoveredSite) -> some View {
        let near = model.nearest(site, installed: availableVersions)
        let resolved = try? ImportSafety.resolvedSafeDocroot(site.path)
        Toggle(isOn: Binding(
            get: { model.selected.contains(site.id) },
            set: { on in if on { model.selected.insert(site.id) } else { model.selected.remove(site.id) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(site.domain).font(KDFont.body)
                    if site.experimental {
                        Text("experimental").font(KDFont.footnote)
                            .foregroundStyle(Color.KDStatus.warning)
                    }
                }
                Text((resolved ?? site.path).path).font(KDFont.footnote).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if resolved == nil {
                    Label("Folder missing or not owned by you — will be skipped",
                          systemImage: "xmark.octagon")
                        .font(KDFont.footnote).foregroundStyle(Color.KDStatus.error)
                }
                if let near, !near.exact {
                    Label("PHP \(site.phpVersion ?? "?") not installed — using \(near.version)",
                          systemImage: "exclamationmark.triangle")
                        .font(KDFont.footnote).foregroundStyle(Color.KDStatus.warning)
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Import Selected") {
                model.importSelected(registry: registry, installed: availableVersions)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.importing || model.selected.isEmpty)
        }
    }
}
