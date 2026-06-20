import Foundation


public struct PHPExtensionInstaller: Sendable {
    public enum InstallResult: Sendable, Equatable {
        case installed
       
        case installedButFailedToLoad(warning: String?)
    }

    public enum InstallError: LocalizedError {
        case noReleaseAvailable(ext: String, phpVersion: String)
        case sharedObjectChecksumMissing(ext: String, phpVersion: String)
        case sharedObjectChecksumMismatch(ext: String, expected: String, actual: String)
        public var errorDescription: String? {
            switch self {
            case .noReleaseAvailable(let ext, let v):
                return "No \(ext) build is available for PHP \(v)."
            case .sharedObjectChecksumMissing(let ext, let v):
                return "\(ext).so for PHP \(v) has no verification record."
            case .sharedObjectChecksumMismatch(let ext, let expected, let actual):
                return "\(ext).so checksum mismatch. Expected \(expected.prefix(12))…, got \(actual.prefix(12))…"
            }
        }
    }

    public enum SharedObjectVerificationStatus: Equatable, Sendable {
        case missingObject
        case missingChecksum
        case verified
        case mismatch(expected: String, actual: String)
    }

    private let paths: AppSupportPaths
    private let catalog: PHPExtensionCatalog
    public init(paths: AppSupportPaths) {
        self.paths = paths
        self.catalog = PHPExtensionCatalog(paths: paths)
    }

   
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

    public func extensionIniURL(extID: String, phpVersion: String) -> URL {
        paths.phpExtConfDir(version: phpVersion).appendingPathComponent("20-\(extID).ini")
    }

    public func sharedObjectURL(extID: String, phpVersion: String) -> URL {
        soURL(extID, phpVersion)
    }

    public func sharedObjectChecksumURL(extID: String, phpVersion: String) -> URL {
        soURL(extID, phpVersion).appendingPathExtension("sha256")
    }

    public func sharedObjectVerificationStatus(extID: String, phpVersion: String) throws -> SharedObjectVerificationStatus {
        let so = soURL(extID, phpVersion)
        guard FileManager.default.fileExists(atPath: so.path) else { return .missingObject }
        let checksum = sharedObjectChecksumURL(extID: extID, phpVersion: phpVersion)
        guard let expected = try? String(contentsOf: checksum, encoding: .utf8)
            .split(whereSeparator: \.isWhitespace).first.map(String.init) else {
            return .missingChecksum
        }
        let actual = try ChecksumVerifier.sha256(of: so)
        return actual.caseInsensitiveCompare(expected) == .orderedSame
            ? .verified
            : .mismatch(expected: expected, actual: actual)
    }

    public func verifySharedObjectChecksum(extID: String, phpVersion: String) throws {
        switch try sharedObjectVerificationStatus(extID: extID, phpVersion: phpVersion) {
        case .verified:
            return
        case .missingObject:
            throw InstallError.noReleaseAvailable(ext: extID, phpVersion: phpVersion)
        case .missingChecksum:
            throw InstallError.sharedObjectChecksumMissing(ext: extID, phpVersion: phpVersion)
        case .mismatch(let expected, let actual):
            throw InstallError.sharedObjectChecksumMismatch(ext: extID, expected: expected, actual: actual)
        }
    }
   
    public func extensionDirIniURL(phpVersion: String) -> URL {
        paths.phpExtConfDir(version: phpVersion).appendingPathComponent("00-extension-dir.ini")
    }

    public func writeExtensionDirIni(phpVersion: String) throws {
        let dir = paths.phpExtConfDir(version: phpVersion)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let body = "extension_dir = \"\(paths.phpModulesDir(version: phpVersion).path)\"\n"
        try body.write(to: extensionDirIniURL(phpVersion: phpVersion), atomically: true, encoding: .utf8)
    }

    public func placeSharedObject(from local: URL, extID: String, phpVersion: String) throws {
        let modules = paths.phpModulesDir(version: phpVersion)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let dest = soURL(extID, phpVersion)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: local, to: dest)
    }

    public func writeExtensionLoadIni(extID: String, phpVersion: String) throws {
        try iniContent(forExtID: extID, phpVersion: phpVersion)
            .write(to: extensionIniURL(extID: extID, phpVersion: phpVersion), atomically: true, encoding: .utf8)
    }

    public func removeExtensionLoadIni(extID: String, phpVersion: String) {
        let url = extensionIniURL(extID: extID, phpVersion: phpVersion)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func finishInstall(extID: String, phpVersion: String) throws {
        try writeExtensionDirIni(phpVersion: phpVersion)
        try writeExtensionLoadIni(extID: extID, phpVersion: phpVersion)
    }

    @discardableResult
    public func installSharedObjectOnly(_ extID: String, phpVersion: String,
                                        onProgress: @escaping @Sendable (RuntimeDownloader.Progress) -> Void = { _ in })
        async throws -> URL {
        guard let release = catalog.release(extID, phpVersion: phpVersion) else {
            throw InstallError.noReleaseAvailable(ext: extID, phpVersion: phpVersion)
        }
        let installed = try await RuntimeDownloader(paths: paths).installSharedObject(
            url: release.url, sha256: release.sha256, soName: "\(extID).so",
            into: paths.phpModulesDir(version: phpVersion), onProgress: onProgress)
        let checksum = try ChecksumVerifier.sha256(of: installed)
        try checksum.write(to: sharedObjectChecksumURL(extID: extID, phpVersion: phpVersion),
                           atomically: true, encoding: .utf8)
        return installed
    }

    @discardableResult
    public func install(_ extID: String, phpVersion: String,
                        onProgress: @escaping @Sendable (RuntimeDownloader.Progress) -> Void = { _ in })
        async throws -> InstallResult {
        try await installSharedObjectOnly(extID, phpVersion: phpVersion, onProgress: onProgress)
        try writeExtensionDirIni(phpVersion: phpVersion)
        PHPModules.invalidate(version: phpVersion)

        let (loaded, warning) = verifyLoad(extID: extID, phpVersion: phpVersion)
        guard loaded else {
            removeExtensionLoadIni(extID: extID, phpVersion: phpVersion)
            return .installedButFailedToLoad(warning: warning)
        }
        try writeExtensionLoadIni(extID: extID, phpVersion: phpVersion)
        PHPModules.invalidate(version: phpVersion)
        return .installed
    }

  
    public func uninstall(_ extID: String, phpVersion: String) throws {
        let fm = FileManager.default
        for url in [extensionIniURL(extID: extID, phpVersion: phpVersion),
                    soURL(extID, phpVersion),
                    sharedObjectChecksumURL(extID: extID, phpVersion: phpVersion)]
        where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        PHPModules.invalidate(version: phpVersion)
    }

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

      
        let modulesList = outText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let loaded = proc.terminationStatus == 0 && modulesList.contains(extID.lowercased())
      
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
