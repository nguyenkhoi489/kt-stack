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
        let phpIni = paths.phpIni(version: request.phpVersion)
        let httpsProvisioner = SiteHTTPSProvisioner(paths: paths,
                                                    tld: registry.tld,
                                                    mkcert: MkcertRunner(mkcert: paths.mkcertBinary, caroot: paths.caDir),
                                                    certMinter: CertMinter(paths: paths,
                                                                           runner: MkcertRunner(mkcert: paths.mkcertBinary,
                                                                                                caroot: paths.caDir)))
        let mysql = MySQLController(paths: paths, agents: LaunchAgentManager(paths: paths))
        let service = SiteInstallService(database: DatabaseProvisioner(ensureEngine: { try await mysql.start() }))

        task = Task {
            do {
                try PHPIniStore(paths: paths).ensureSeeded(version: request.phpVersion)
                let installer = try await buildInstaller(request: request, php: php, phpIni: phpIni, paths: paths)
                let site = try await service.install(request, installer: installer, register: { folder in
                    try await MainActor.run {
                        try registry.add(folder: folder, phpVersion: request.phpVersion, databaseName: request.databaseName)
                    }
                }, emit: { event in
                    Task { @MainActor in self.events.append(event) }
                })
                await MainActor.run {
                    self.events.append(InstallEvent(phase: .finalizing, message: "Enabling HTTPS…"))
                }
                try httpsProvisioner.enableHTTPS(for: site)
                registry.setSecure(site, true)
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

    func reset() {
        error = nil
        events = []
    }

    private func buildInstaller(request: NewSiteRequest, php: URL, phpIni: URL, paths: AppSupportPaths) async throws -> SiteInstaller {
        switch request.kind {
        case .wordpress:
            let phar = try await PharProvisioner.wpCli(paths: paths).provision()
            return WordPressInstaller(php: php, phpIni: phpIni, wpCliPhar: phar)
        case .laravel:
            let phar = try await ComposerProvisioner(paths: paths).provision()
            return LaravelInstaller(php: php, phpIni: phpIni, composerPhar: phar)
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
    @State private var siteTitle = ""
    @State private var adminUser = "admin"
    @State private var adminEmail = "admin@example.com"
    @State private var advancedExpanded = false

    private var slug: String { SiteInspector.slug(name) }
    private var domain: String { "\(slug).\(tld)" }
    private var hasOverlayState: Bool {
        model.installing || model.finished || model.error != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSiteHeader(onDismiss: { dismiss() })
                .padding(.horizontal, KDSpacing.space5)
                .padding(.top, KDSpacing.space5)
                .padding(.bottom, KDSpacing.space4)

            if hasOverlayState {
                Divider()
                SiteInstallProgressView(events: model.events, error: model.error)
                    .padding(KDSpacing.space5)
            } else {
                ScrollView {
                    NewSiteFormBody(
                        availableVersions: availableVersions,
                        tld: tld,
                        name: $name,
                        kind: $kind,
                        phpVersion: $phpVersion,
                        adminPassword: $adminPassword,
                        siteTitle: $siteTitle,
                        adminUser: $adminUser,
                        adminEmail: $adminEmail,
                        advancedExpanded: $advancedExpanded,
                        regeneratePassword: NewSiteSheet.randomPassword
                    )
                    .padding(.horizontal, KDSpacing.space5)
                    .padding(.vertical, KDSpacing.space2)
                }
            }

            Divider()
            footer
                .padding(KDSpacing.space4)
        }
        .frame(width: 560)
        .frame(minHeight: 420, maxHeight: 720)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var footer: some View {
        HStack(spacing: KDSpacing.space2) {
            if model.finished {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.KDStatus.info)
            } else if model.installing {
                Spacer()
                Button("Cancel") { model.cancel() }
            } else if model.error != nil {
                Spacer()
                Button("Back") { model.reset() }
                    .keyboardShortcut(.cancelAction)
                Button("Try Again") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.KDStatus.info)
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: create) {
                    HStack(spacing: KDSpacing.space1) {
                        Image(systemName: "plus")
                        Text("Create Site")
                    }
                    .padding(.horizontal, KDSpacing.space2)
                    .padding(.vertical, 2)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.KDStatus.info)
                .disabled(slug.isEmpty || availableVersions.isEmpty)
            }
        }
    }

    private func create() {
        let request = NewSiteRequest(
            name: slug, kind: kind, phpVersion: phpVersion,
            folder: sitesRoot.appendingPathComponent(slug, isDirectory: true),
            domain: domain, databaseName: slug,
            siteTitle: siteTitle.isEmpty ? slug : siteTitle,
            adminUser: adminUser.isEmpty ? "admin" : adminUser,
            adminEmail: adminEmail.isEmpty ? "admin@example.com" : adminEmail,
            adminPassword: kind == .wordpress ? adminPassword : "")
        model.install(request: request, registry: registry, openOnFinish: true)
    }

    static func randomPassword() -> String {
        let chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<16).map { _ in chars.randomElement()! })
    }
}
