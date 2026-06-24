import SwiftUI
import AppKit
import KTStackKit

@MainActor
final class RestoreBackupModel: ObservableObject {
    enum Stage: Equatable { case idle, ready, running, success, failed }

    let site: Site

    @Published private(set) var backupFile: URL?
    @Published private(set) var kind: WordPressBackupKind?
    @Published var phpVersion: String
    @Published var secure: Bool
    @Published var trusted = false
    @Published private(set) var stage: Stage = .idle
    @Published private(set) var phase: RestorePhase?
    @Published private(set) var message = ""
    @Published private(set) var warnings: [String] = []
    @Published var error: String?

    private var task: Task<Void, Never>?

    init(site: Site) {
        self.site = site
        self.phpVersion = site.phpVersion
        self.secure = site.secure
    }

    var canRestore: Bool {
        backupFile != nil && kind != nil && trusted && stage != .running
    }

    func selectFile(_ url: URL, installed: [String]) {
        do {
            kind = try WordPressBackupInspector().inspect(url)
            backupFile = url
            if !installed.contains(phpVersion) { phpVersion = installed.first ?? site.phpVersion }
            error = nil
            stage = .ready
        } catch {
            self.error = error.localizedDescription
            kind = nil
            backupFile = nil
            stage = .idle
        }
    }

    func restore(registry: SiteRegistry, server: LocalServerController) {
        guard let backupFile, canRestore else { return }
        stage = .running
        error = nil
        warnings = []
        phase = .detecting
        message = ""

        let site = self.site
        let request = RestoreRequest(backupFile: backupFile,
                                     siteFolder: URL(fileURLWithPath: site.path, isDirectory: true),
                                     siteDomain: site.domain,
                                     phpVersion: phpVersion, secure: secure)
        let paths = AppSupportPaths()
        let mysql = MySQLController(paths: paths, agents: LaunchAgentManager(paths: paths))
        let mkcert = MkcertRunner(mkcert: paths.mkcertBinary, caroot: paths.caDir)
        let httpsProvisioner = SiteHTTPSProvisioner(paths: paths, tld: registry.tld,
                                                    mkcert: mkcert,
                                                    certMinter: CertMinter(paths: paths, runner: mkcert))
        let phpVersion = self.phpVersion
        let service = WordPressRestoreService(
            paths: paths,
            ensureEngine: { try await mysql.start() },
            applyServerConfig: { await MainActor.run { server.reconcileAfterRuntimeChange() } },
            enableHTTPS: {
                try httpsProvisioner.enableHTTPS(for: site)
                await MainActor.run { registry.setSecure(site, true) }
            },
            finalizeSite: { database in
                await MainActor.run {
                    registry.setDatabaseName(site, database)
                    registry.setPHPVersion(site, to: phpVersion)
                    registry.reinspect(site)
                }
            })

        task = Task {
            do {
                let outcome = try await service.restore(request) { event in
                    Task { @MainActor in
                        self.phase = event.phase
                        self.message = event.message
                    }
                }
                self.warnings = outcome.warnings
                self.stage = .success
            } catch is CancellationError {
                self.error = "Restore cancelled."
                self.stage = .failed
            } catch {
                self.error = error.localizedDescription
                self.stage = .failed
            }
        }
    }

    func cancel() { task?.cancel() }
}
