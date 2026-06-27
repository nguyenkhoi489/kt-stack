import SwiftUI
import AppKit
import KTStackKit

@MainActor
final class NewSiteModel: ObservableObject {
    @Published private(set) var events: [InstallEvent] = []
    @Published private(set) var installing = false
    @Published private(set) var finished = false
    @Published var error: String?

    private var task: Task<Void, Never>?

    func install(request: NewSiteRequest, registry: SiteRegistry, openOnFinish: Bool, enableHTTPS: Bool = true) {
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
                if enableHTTPS {
                    await MainActor.run {
                        self.events.append(InstallEvent(phase: .finalizing, message: "Enabling HTTPS…"))
                    }
                    try httpsProvisioner.enableHTTPS(for: site)
                    registry.setSecure(site, true)
                }
                finished = true
                if openOnFinish {
                    let scheme = enableHTTPS ? "https" : "http"
                    if let url = URL(string: "\(scheme)://\(site.domain)/") { NSWorkspace.shared.open(url) }
                }
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
        case .empty:
            return EmptySiteInstaller()
        }
    }
}

