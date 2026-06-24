import Foundation

public final class WordPressRestoreService: Sendable {
    private let paths: AppSupportPaths
    private let dumpService: DumpService
    private let provisioner: DatabaseProvisioner
    private let staging: RestoreStagingArea
    private let applyServerConfig: @Sendable () async throws -> Void
    private let enableHTTPS: @Sendable () async throws -> Void
    private let finalizeSite: @Sendable (String) async -> Void

    public init(paths: AppSupportPaths,
                dumpService: DumpService = DumpService(),
                ensureEngine: @escaping @Sendable () async throws -> Void,
                applyServerConfig: @escaping @Sendable () async throws -> Void,
                enableHTTPS: @escaping @Sendable () async throws -> Void,
                finalizeSite: @escaping @Sendable (String) async -> Void) {
        self.paths = paths
        self.dumpService = dumpService
        self.provisioner = DatabaseProvisioner(ensureEngine: ensureEngine)
        self.staging = RestoreStagingArea(paths: paths)
        self.applyServerConfig = applyServerConfig
        self.enableHTTPS = enableHTTPS
        self.finalizeSite = finalizeSite
    }

    public func restore(_ request: RestoreRequest,
                        emit: @Sendable @escaping (RestoreEvent) -> Void) async throws -> RestoreOutcome {
        let stagingRoot = try staging.make()
        defer { staging.discard(stagingRoot) }

        var undo: [@Sendable () async -> Void] = []
        func rollback() async { for step in undo.reversed() { await step() } }

        do {
            let php = paths.phpBinary(version: request.phpVersion)
            let iniURL = paths.phpIni(version: request.phpVersion)
            let phpIni = FileManager.default.fileExists(atPath: iniURL.path) ? iniURL : nil
            let wpCliPhar = paths.wpCliPhar
            var warnings: [String] = []

            emit(RestoreEvent(phase: .detecting, message: "Inspecting backup…"))
            let kind = try WordPressBackupInspector().inspect(request.backupFile)
            let extractor: RestoreArchiveExtractor = kind == .aioWpress
                ? WPressArchiveReader() : DuplicatorArchiveReader()

            emit(RestoreEvent(phase: .extracting, message: "Extracting \(kind.label) backup…"))
            let payload = try await extractor.extract(request.backupFile, into: stagingRoot) {
                emit(RestoreEvent(phase: .extracting, message: $0))
            }

            try await preflight(request: request, wpCliPhar: wpCliPhar)

            let prepared = stagingRoot.appendingPathComponent("prepared", isDirectory: true)

            try Task.checkCancellation()
            emit(RestoreEvent(phase: .reconcilingCore, message: "Preparing WordPress files…"))
            let reconcileResult = try await WordPressCoreReconciler(php: php, phpIni: phpIni, wpCliPhar: wpCliPhar)
                .reconcile(payload: payload, targetDocroot: prepared) {
                    emit(RestoreEvent(phase: .reconcilingCore, message: $0))
                }
            WordPressPayloadMetadata.stripInstallerScaffolding(docroot: prepared)
            if reconcileResult.usedLatestFallback, let requested = reconcileResult.requestedVersion {
                warnings.append("WordPress \(requested) was unavailable; the latest stable release was installed instead.")
            }

            try Task.checkCancellation()
            let databaseBase = RestoreNaming.databaseBase(from: RestoreNaming.label(from: request.siteDomain))
            let database = try await RestoreNaming.uniqueName(base: databaseBase) {
                try await provisioner.exists($0)
            }
            emit(RestoreEvent(phase: .creatingDatabase, message: "Creating database \(database)…"))
            try await provisioner.createDatabase(database)
            undo.append { try? await self.provisioner.dropDatabase(database) }

            try Task.checkCancellation()
            emit(RestoreEvent(phase: .importingDatabase, message: "Importing database…"))
            try await dumpService.importDump(profile: .managedMySQL, password: nil,
                                             database: database, from: payload.sqlDump)

            if request.repairEncoding {
                try Task.checkCancellation()
                emit(RestoreEvent(phase: .repairingEncoding, message: "Repairing text encoding…"))
                try WordPressEncodingRepair(php: php, phpIni: phpIni)
                    .repair(database: database, tablePrefix: payload.tablePrefix, workDir: stagingRoot) {
                        emit(RestoreEvent(phase: .repairingEncoding, message: $0))
                    }
            }

            try Task.checkCancellation()
            emit(RestoreEvent(phase: .writingConfig, message: "Writing wp-config.php…"))
            try WPConfigWriter(php: php, phpIni: phpIni, wpCliPhar: wpCliPhar)
                .write(into: prepared, database: database, tablePrefix: payload.tablePrefix) {
                    emit(RestoreEvent(phase: .writingConfig, message: $0))
                }

            try Task.checkCancellation()
            let searchReplace = WordPressSearchReplaceRunner(php: php, phpIni: phpIni, wpCliPhar: wpCliPhar)
            let newURL = "https://\(request.siteDomain)"
            guard let oldURL = payload.sourceURL ?? searchReplace.currentSiteURL(docroot: prepared) else {
                throw RestoreServiceError.sourceURLUnresolved
            }
            emit(RestoreEvent(phase: .searchReplace, message: "Rewriting site address…"))
            try await searchReplace.run(docroot: prepared, oldURL: oldURL, newURL: newURL) {
                emit(RestoreEvent(phase: .searchReplace, message: $0))
            }

            try Task.checkCancellation()
            emit(RestoreEvent(phase: .installingFiles, message: "Installing files into \(request.siteDomain)…"))
            try swapIntoSite(prepared: prepared, siteFolder: request.siteFolder, stagingRoot: stagingRoot)

            await finalizeSite(database)

            try Task.checkCancellation()
            emit(RestoreEvent(phase: .configuringServer, message: "Configuring web server…"))
            try await applyServerConfig()
            if request.secure {
                try await enableHTTPS()
                try await applyServerConfig()
            }

            warnings.append("Hardcoded URLs inside PHP files are not rewritten automatically.")
            emit(RestoreEvent(phase: .done, message: "Restored at \(newURL)"))
            return RestoreOutcome(domain: request.siteDomain, warnings: warnings)
        } catch {
            await rollback()
            throw error
        }
    }

    private func swapIntoSite(prepared: URL, siteFolder: URL, stagingRoot: URL) throws {
        let fm = FileManager.default
        let replaced = stagingRoot.appendingPathComponent("replaced-site", isDirectory: true)
        let hadFolder = fm.fileExists(atPath: siteFolder.path)
        if hadFolder { try fm.moveItem(at: siteFolder, to: replaced) }
        do {
            try fm.moveItem(at: prepared, to: siteFolder)
        } catch {
            if hadFolder, !fm.fileExists(atPath: siteFolder.path) {
                try? fm.moveItem(at: replaced, to: siteFolder)
            }
            throw error
        }
    }

    private func preflight(request: RestoreRequest, wpCliPhar: URL) async throws {
        let installed = BundledPHP.availableVersions(php: paths.phpRuntimesRoot)
        guard installed.contains(request.phpVersion) else {
            throw RestoreServiceError.phpVersionNotInstalled(request.phpVersion)
        }
        _ = try await PharProvisioner.wpCli(paths: paths).provision()
    }
}
