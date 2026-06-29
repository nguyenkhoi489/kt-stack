import AppKit
import KTStackKit
import SwiftUI

enum ImportError: LocalizedError {
    case databaseExists(String)

    var errorDescription: String? {
        switch self {
        case let .databaseExists(name):
            "A database named “\(name)” already exists. Disable “Create database” or rename the folder."
        }
    }
}

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
        let httpsProvisioner = SiteHTTPSProvisioner(
            paths: paths,
            tld: registry.tld,
            mkcert: MkcertRunner(mkcert: paths.mkcertBinary, caroot: paths.caDir),
            certMinter: CertMinter(
                paths: paths,
                runner: MkcertRunner(
                    mkcert: paths.mkcertBinary,
                    caroot: paths.caDir
                )
            )
        )
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

    func importExisting(
        folder: URL,
        domain: String,
        phpVersion: String,
        createDatabase: Bool,
        enableHTTPS: Bool,
        registry: SiteRegistry,
        openOnFinish: Bool = true
    ) {
        guard !installing else { return }
        let safe: URL
        do {
            safe = try ImportSafety.resolvedSafeDocroot(folder)
        } catch {
            self.error = error.localizedDescription
            return
        }
        if registry.sites.contains(where: {
            URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().standardizedFileURL.path == safe.path
        }) {
            error = "“\(safe.lastPathComponent)” is already registered."
            return
        }
        do {
            try registry.validateDomain(domain)
        } catch {
            self.error = error.localizedDescription
            return
        }
        installing = true
        error = nil
        events = []
        let paths = AppSupportPaths()
        let httpsProvisioner = SiteHTTPSProvisioner(
            paths: paths,
            tld: registry.tld,
            mkcert: MkcertRunner(mkcert: paths.mkcertBinary, caroot: paths.caDir),
            certMinter: CertMinter(
                paths: paths,
                runner: MkcertRunner(
                    mkcert: paths.mkcertBinary,
                    caroot: paths.caDir
                )
            )
        )
        let mysql = MySQLController(paths: paths, agents: LaunchAgentManager(paths: paths))
        let database = DatabaseProvisioner(ensureEngine: { try await mysql.start() })
        let databaseName = createDatabase ? SiteInspector.slug(safe.lastPathComponent) : nil

        task = Task {
            do {
                try PHPIniStore(paths: paths).ensureSeeded(version: phpVersion)
                if let databaseName {
                    emit(.configuringDatabase, "Creating database “\(databaseName)”…")
                    if try await database.exists(databaseName) {
                        throw ImportError.databaseExists(databaseName)
                    }
                    try await database.createDatabase(databaseName)
                }
                emit(.preparing, "Registering \(safe.lastPathComponent)…")
                let registered = try await MainActor.run {
                    try registry.add(
                        folder: safe,
                        phpVersion: phpVersion,
                        respectProjectMarkers: false,
                        databaseName: databaseName
                    )
                }
                if registered.domain != domain {
                    try await MainActor.run { try registry.editDomain(registered, to: domain) }
                }
                let site = await MainActor.run {
                    registry.sites.first(where: { $0.id == registered.id }) ?? registered
                }
                if enableHTTPS {
                    emit(.finalizing, "Enabling HTTPS…")
                    try httpsProvisioner.enableHTTPS(for: site)
                    await MainActor.run { registry.setSecure(site, true) }
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

    private func emit(_ phase: InstallPhase, _ message: String) {
        Task { @MainActor in self.events.append(InstallEvent(phase: phase, message: message)) }
    }

    func cancel() {
        task?.cancel()
    }

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
