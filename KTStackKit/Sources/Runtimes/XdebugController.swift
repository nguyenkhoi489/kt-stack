import Foundation

public final class XdebugController: @unchecked Sendable {
    public typealias LoadVerifier = @Sendable (String) -> (loaded: Bool, warning: String?)

    public enum XdebugError: LocalizedError, Equatable {
        case notSupported(String)
        case verificationFailed(String)
        case rollbackFailed(String, String)
        public var errorDescription: String? {
            switch self {
            case let .notSupported(v): "Xdebug isn't available for PHP \(v) on this platform."
            case let .verificationFailed(w): "Xdebug failed to load: \(w)"
            case let .rollbackFailed(reload, rollback):
                "Xdebug reload failed (\(reload)) and rollback failed (\(rollback))."
            }
        }
    }

    public static let clientPort = 9003

    private let paths: AppSupportPaths
    private let catalog: PHPExtensionCatalog
    private let installer: PHPExtensionInstaller
    private let reloadPool: (String) async throws -> Void
    private let loadVerifier: LoadVerifier

    public init(
        paths: AppSupportPaths,
        reloadPool: @escaping (String) async throws -> Void,
        loadVerifier: LoadVerifier? = nil
    ) {
        self.paths = paths
        catalog = PHPExtensionCatalog(paths: paths)
        let installer = PHPExtensionInstaller(paths: paths)
        self.installer = installer
        self.reloadPool = reloadPool
        self.loadVerifier = loadVerifier ?? { version in
            installer.verifyLoad(extID: "xdebug", phpVersion: version)
        }
    }

    public func isSupported(version: String) -> Bool {
        catalog.release("xdebug", phpVersion: version) != nil
    }

    public func isEnabled(version: String) -> Bool {
        FileManager.default.fileExists(atPath: confURL(version: version).path)
    }

    public func confURL(version: String) -> URL {
        installer.extensionIniURL(extID: "xdebug", phpVersion: version)
    }

    public func iniContent(version: String) -> String {
        let soPath = paths.phpModulesDir(version: version).appendingPathComponent("xdebug.so").path
        return """
        zend_extension=\(soPath)
        xdebug.mode=debug
        xdebug.client_port=\(Self.clientPort)
        xdebug.start_with_request=yes

        """
    }

    public func enable(version: String) async throws {
        guard isSupported(version: version) else { throw XdebugError.notSupported(version) }

        let conf = confURL(version: version)
        let previous = try? Data(contentsOf: conf)
        switch try installer.verificationStatus(extID: "xdebug", phpVersion: version) {
        case .verified:
            break
        case .missingObject, .missingChecksum:
            do { try await installer.installSharedObjectOnly("xdebug", phpVersion: version) }
            catch { throw XdebugError.verificationFailed(error.localizedDescription) }
        case .mismatch:
            do { try installer.verifySharedObjectChecksum(extID: "xdebug", phpVersion: version) }
            catch {
                throw XdebugError.verificationFailed(error.localizedDescription)
            }
        }

        let load = loadVerifier(version)
        guard load.loaded else {
            throw XdebugError.verificationFailed(load.warning ?? "shared object did not load")
        }

        try FileManager.default.createDirectory(
            at: conf.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try iniContent(version: version).data(using: .utf8)!.write(to: conf, options: .atomic)
        PHPModules.invalidate(version: version)
        do {
            try await reloadPool(version)
        } catch let reloadError {
            do { try restore(conf: conf, to: previous) }
            catch let rollbackError {
                throw XdebugError.rollbackFailed(String(describing: reloadError), String(describing: rollbackError))
            }
            do { try await reloadPool(version) }
            catch let rollbackReloadError {
                throw XdebugError.rollbackFailed(String(describing: reloadError), String(describing: rollbackReloadError))
            }
            throw reloadError
        }
    }

    public func disable(version: String) async throws {
        let conf = confURL(version: version)
        guard let previous = try? Data(contentsOf: conf) else { return }
        try FileManager.default.removeItem(at: conf)
        PHPModules.invalidate(version: version)
        do {
            try await reloadPool(version)
        } catch let reloadError {
            do { try restore(conf: conf, to: previous) }
            catch let rollbackError {
                throw XdebugError.rollbackFailed(String(describing: reloadError), String(describing: rollbackError))
            }
            do { try await reloadPool(version) }
            catch let rollbackReloadError {
                throw XdebugError.rollbackFailed(String(describing: reloadError), String(describing: rollbackReloadError))
            }
            throw reloadError
        }
    }

    private func restore(conf: URL, to data: Data?) throws {
        if let data {
            try data.write(to: conf, options: .atomic)
        } else if FileManager.default.fileExists(atPath: conf.path) {
            try FileManager.default.removeItem(at: conf)
        }
        PHPModules.invalidate(version: version(from: conf))
    }

    private func version(from conf: URL) -> String {
        conf.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
    }
}
