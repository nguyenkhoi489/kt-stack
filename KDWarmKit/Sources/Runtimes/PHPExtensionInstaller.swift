import Foundation

/// Install/uninstall lifecycle for the optional shared-extension layer. Loading is driven by
/// `PHP_INI_SCAN_DIR` (set on the php-fpm spec) + a low-numbered `extension_dir` ini, NOT pool
/// `php_admin_value` (modules load at MINIT, before pool values apply). The per-version `php.ini` is
/// untouched. The CALLER restarts the pool after install/uninstall — a `dlopen`'d `.so` stays loaded
/// until the master restarts, so a reload is insufficient to load or unload one.
public struct PHPExtensionInstaller: Sendable {
    public enum InstallResult: Sendable, Equatable {
        case installed
        /// `.so` placed + ini written, but `php` did not load it (ABI/signature) — surface, don't hide.
        case installedButFailedToLoad(warning: String?)
    }

    public enum InstallError: LocalizedError {
        case noReleaseAvailable(ext: String, phpVersion: String)
        public var errorDescription: String? {
            switch self {
            case .noReleaseAvailable(let ext, let v):
                return "No \(ext) build is available for PHP \(v)."
            }
        }
    }

    private let paths: AppSupportPaths
    private let catalog: PHPExtensionCatalog
    public init(paths: AppSupportPaths) {
        self.paths = paths
        self.catalog = PHPExtensionCatalog(paths: paths)
    }

    // MARK: - Ini generation

    /// The scan-dir ini body for an extension. A plain module resolves `<ext>.so` via `extension_dir`;
    /// a Zend extension MUST be referenced by an ABSOLUTE path (`extension_dir` does not apply to it).
    public func iniContent(forExtID extID: String, phpVersion: String) -> String {
        let directive = PHPExtensionCatalog.descriptor(extID)?.loadDirective ?? .module
        switch directive {
        case .module:
            return "extension=\(extID).so\n"
        case .zendExtension:
            let abs = soURL(extID, phpVersion).path
            return "zend_extension=\(abs)\n"
        }
    }

    /// `conf.d/20-<ext>.ini` — the per-extension load directive (20- so it loads after the 00- dir ini).
    public func extensionIniURL(extID: String, phpVersion: String) -> URL {
        paths.phpExtConfDir(version: phpVersion).appendingPathComponent("20-\(extID).ini")
    }
    /// `conf.d/00-extension-dir.ini` — sets `extension_dir`, loaded before any `20-<ext>.ini`.
    public func extensionDirIniURL(phpVersion: String) -> URL {
        paths.phpExtConfDir(version: phpVersion).appendingPathComponent("00-extension-dir.ini")
    }

    // MARK: - File operations

    /// Write the shared `extension_dir` ini pointing at this version's modules dir.
    public func writeExtensionDirIni(phpVersion: String) throws {
        let dir = paths.phpExtConfDir(version: phpVersion)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let body = "extension_dir = \"\(paths.phpModulesDir(version: phpVersion).path)\"\n"
        try body.write(to: extensionDirIniURL(phpVersion: phpVersion), atomically: true, encoding: .utf8)
    }

    /// Copy a local `.so` into the version's modules dir, replacing ONLY that ext's file — sibling
    /// extensions are left intact (red-team C1). Used for a local mirror / tests; the network path
    /// uses `RuntimeDownloader.installSharedObject`, which applies the same no-sibling-wipe rule.
    public func placeSharedObject(from local: URL, extID: String, phpVersion: String) throws {
        let modules = paths.phpModulesDir(version: phpVersion)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let dest = soURL(extID, phpVersion)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: local, to: dest)
    }

    /// Write the extension-dir ini + the per-extension ini (the `.so` must already be placed).
    public func finishInstall(extID: String, phpVersion: String) throws {
        try writeExtensionDirIni(phpVersion: phpVersion)
        try iniContent(forExtID: extID, phpVersion: phpVersion)
            .write(to: extensionIniURL(extID: extID, phpVersion: phpVersion), atomically: true, encoding: .utf8)
    }

    // MARK: - Lifecycle

    /// Download + verify + place the `.so`, write the inis, then verify it actually loads. The caller
    /// RESTARTS the pool afterwards so the running master picks it up.
    @discardableResult
    public func install(_ extID: String, phpVersion: String,
                        onProgress: @escaping @Sendable (RuntimeDownloader.Progress) -> Void = { _ in })
        async throws -> InstallResult {
        guard let release = catalog.release(extID, phpVersion: phpVersion) else {
            throw InstallError.noReleaseAvailable(ext: extID, phpVersion: phpVersion)
        }
        try await RuntimeDownloader(paths: paths).installSharedObject(
            url: release.url, sha256: release.sha256, soName: "\(extID).so",
            into: paths.phpModulesDir(version: phpVersion), onProgress: onProgress)
        try finishInstall(extID: extID, phpVersion: phpVersion)
        PHPModules.invalidate(version: phpVersion)   // status re-reads after the change (L2)

        let (loaded, warning) = verifyLoad(extID: extID, phpVersion: phpVersion)
        return loaded ? .installed : .installedButFailedToLoad(warning: warning)
    }

    /// Remove the ext's ini + `.so`. The caller RESTARTS the pool to actually unload it (reload won't).
    public func uninstall(_ extID: String, phpVersion: String) throws {
        let fm = FileManager.default
        for url in [extensionIniURL(extID: extID, phpVersion: phpVersion), soURL(extID, phpVersion)]
        where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        PHPModules.invalidate(version: phpVersion)
    }

    // MARK: - Load verification (silent-fail detection, red-team H2)

    /// Run `php -d extension_dir=… -d (zend_)extension=<so> -m`, capturing stderr. Returns whether the
    /// module loaded (present in `php -m`, exit 0) plus any startup Warning text — so a `.so` that
    /// dlopens-but-fails (ABI/signature) is reported, not silently treated as "not installed".
    public func verifyLoad(extID: String, phpVersion: String) -> (loaded: Bool, warning: String?) {
        let php = paths.phpBinary(version: phpVersion)
        guard FileManager.default.isExecutableFile(atPath: php.path) else { return (false, nil) }

        let modules = paths.phpModulesDir(version: phpVersion)
        let directive = PHPExtensionCatalog.descriptor(extID)?.loadDirective ?? .module
        var args = ["-d", "extension_dir=\(modules.path)"]
        switch directive {
        case .module:        args += ["-d", "extension=\(extID).so"]
        case .zendExtension: args += ["-d", "zend_extension=\(soURL(extID, phpVersion).path)"]
        }
        args.append("-m")

        let proc = Process()
        proc.executableURL = php
        proc.arguments = args
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out; proc.standardError = err
        do { try proc.run() } catch { return (false, error.localizedDescription) }
        let outText = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errText = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        proc.waitUntilExit()

        // Loaded only if `php -m` lists the module as its OWN line — a startup Warning that merely
        // mentions "<ext>.so" must not count as loaded (exact line match, not substring).
        let modulesList = outText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let loaded = proc.terminationStatus == 0 && modulesList.contains(extID.lowercased())
        // PHP routes the "Unable to load dynamic library" startup warning to stdout OR stderr depending
        // on ini — scan both so a silent load failure is always surfaced.
        // "Unable to load dynamic library" (extension=) and "Failed loading … Zend extension"
        // (zend_extension=) are the two startup-failure signatures to surface.
        let warning = (errText + "\n" + outText).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.range(of: "Unable to load", options: .caseInsensitive) != nil
                  || $0.range(of: "Failed loading", options: .caseInsensitive) != nil }
        return (loaded, loaded ? nil : warning)
    }

    private func soURL(_ extID: String, _ phpVersion: String) -> URL {
        paths.phpModulesDir(version: phpVersion).appendingPathComponent("\(extID).so")
    }
}
