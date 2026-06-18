import SwiftUI
import AppKit
import KDWarmKit

@MainActor
final class NewSiteModel: ObservableObject {
    @Published private(set) var events: [InstallEvent] = []
    @Published private(set) var installing = false
    @Published private(set) var finished = false
    @Published var error: String?

    private var task: Task<Void, Never>?

    func install(request: NewSiteRequest, registry: SiteRegistry, openOnFinish: Bool) {
        guard !installing else { return }
        do {
            try registry.validateDomain(request.domain)
        } catch {
            self.error = error.localizedDescription
            return
        }
        installing = true
        error = nil
        events = []
        let paths = AppSupportPaths()
        let php = paths.phpBinary(version: request.phpVersion)
        let mysql = MySQLController(paths: paths, agents: LaunchAgentManager(paths: paths))
        let service = SiteInstallService(database: DatabaseProvisioner(ensureEngine: { try await mysql.start() }))

        task = Task {
            do {
                let installer = try await buildInstaller(request: request, php: php, paths: paths)
                let site = try await service.install(request, installer: installer, register: { folder in
                    try await MainActor.run { try registry.add(folder: folder, phpVersion: request.phpVersion) }
                }, emit: { event in
                    Task { @MainActor in self.events.append(event) }
                })
                finished = true
                if openOnFinish { NSWorkspace.shared.open(URL(string: "https://\(site.domain)/")!) }
            } catch is CancellationError {
                error = "Cancelled."
            } catch {
                self.error = error.localizedDescription
            }
            installing = false
        }
    }

    func cancel() { task?.cancel() }

    private func buildInstaller(request: NewSiteRequest, php: URL, paths: AppSupportPaths) async throws -> SiteInstaller {
        switch request.kind {
        case .wordpress:
            let phar = try await PharProvisioner.wpCli(paths: paths).provision()
            return WordPressInstaller(php: php, wpCliPhar: phar)
        case .laravel:
            let phar = try await ComposerProvisioner(paths: paths).provision()
            return LaravelInstaller(php: php, composerPhar: phar)
        }
    }
}

struct NewSiteSheet: View {
    @ObservedObject var registry: SiteRegistry
    let availableVersions: [String]
    let sitesRoot: URL
    let tld: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = NewSiteModel()

    @State private var name = ""
    @State private var kind: NewSiteKind = .wordpress
    @State private var phpVersion = BundledPHP.defaultVersion
    @State private var adminPassword = NewSiteSheet.randomPassword()

    private var slug: String { SiteInspector.slug(name) }
    private var domain: String { "\(slug).\(tld)" }

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Text("New Site").font(KDFont.title)
            if model.installing || model.finished {
                SiteInstallProgressView(events: model.events, error: model.error)
            } else {
                form
            }
            controls
        }
        .padding(KDSpacing.space4)
        .frame(width: 480)
    }

    private var form: some View {
        Grid(alignment: .leading, verticalSpacing: KDSpacing.space2) {
            GridRow {
                Text("Name").foregroundStyle(.secondary)
                TextField("my-site", text: $name).font(KDFont.mono).frame(width: 260)
            }
            GridRow {
                Text("Type").foregroundStyle(.secondary)
                Picker("", selection: $kind) {
                    ForEach(NewSiteKind.allCases) { Text($0.label).tag($0) }
                }.labelsHidden().fixedSize()
            }
            GridRow {
                Text("PHP").foregroundStyle(.secondary)
                Picker("", selection: $phpVersion) {
                    ForEach(availableVersions, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().fixedSize()
            }
            if kind == .wordpress {
                GridRow {
                    Text("Admin password").foregroundStyle(.secondary)
                    TextField("", text: $adminPassword).font(KDFont.mono).frame(width: 260)
                }
            }
            if !name.isEmpty {
                GridRow {
                    Text("Domain").foregroundStyle(.secondary)
                    Text("https://\(domain)").font(KDFont.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            Spacer()
            if model.finished {
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            } else if model.installing {
                Button("Cancel") { model.cancel() }
            } else {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create Site") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(slug.isEmpty || availableVersions.isEmpty)
            }
        }
    }

    private func create() {
        let request = NewSiteRequest(
            name: slug, kind: kind, phpVersion: phpVersion,
            folder: sitesRoot.appendingPathComponent(slug, isDirectory: true),
            domain: domain, databaseName: slug, siteTitle: slug,
            adminPassword: kind == .wordpress ? adminPassword : "")
        model.install(request: request, registry: registry, openOnFinish: true)
    }

    static func randomPassword() -> String {
        let chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<16).map { _ in chars.randomElement()! })
    }
}
