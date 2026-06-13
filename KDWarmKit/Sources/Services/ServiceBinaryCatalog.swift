import Foundation

/// A downloadable database engine build (Redis/PostgreSQL/MySQL). KDWarm ships lean — these are NOT
/// bundled in the DMG; the user installs them on demand via the Services UI, the same verified
/// download → checksum → extract path as the runtime manager. The artifact is a self-contained
/// `<kind>-<version>/{bin,lib,share}` tree, so an engine runs from `runtimes/<kind>/<version>/`.
public struct ServiceBinaryRelease: Sendable, Hashable, Identifiable {
    public let kind: ServiceKind
    public let version: String
    public let sha256: String

    public var id: String { "\(kind.rawValue)-\(version)" }
    public var fileName: String { "\(kind.rawValue)-\(version)-\(ServiceBinaryCatalog.arch).tar.gz" }
    public var url: URL { ServiceBinaryCatalog.releaseBaseURL.appendingPathComponent(fileName) }
}

/// Installed-engine discovery + the on-demand download manifest for database services. Installed
/// engines are found by scanning `runtimes/<kind>/<version>/` for the kind's marker executable; the
/// manifest lists verified builds (real checksums from the build pipeline) — MySQL, Redis, Postgres,
/// each Developer-ID signed + notarized.
public struct ServiceBinaryCatalog: Sendable {
    /// Where engine artifacts are hosted: the project's GitHub Releases download path (self-built,
    /// relocatable Redis/Postgres — no upstream macOS drop-in exists). `appendingPathComponent(fileName)`
    /// resolves to `…/releases/download/<tag>/<kind>-<version>-<arch>.tar.gz`. Overridable for tests /
    /// a local mirror.
    public nonisolated(unsafe) static var releaseBaseURL =
        URL(string: "https://github.com/nguyenkhoi489/kd-warm/releases/download/binaries-v1")!

    public static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    /// Verified engine builds (checksums emitted by `scripts/build-*-relocatable.sh`).
    public static let manifest: [ServiceBinaryRelease] = [
        ServiceBinaryRelease(kind: .mysql, version: "9.6.0",
                             sha256: "e8bf680f8372a9cd4fab38b120753fef1ffb8980d8b5554d64c7186e671616b0"),
        ServiceBinaryRelease(kind: .redis, version: "7.4.2",
                             sha256: "b9e086c252492561e4a53820589cb893ad07bbd4b1c08f38fcf87836ad1cb6e9"),
        ServiceBinaryRelease(kind: .postgres, version: "17.10",
                             sha256: "2fc58f9f78376b79f5007bfbbd6f724f5f34d81cd429ef6b0c9696ad8617d698"),
    ]

    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) { self.paths = paths }

    /// Primary marker executable proving an engine is installed + runnable.
    public static func marker(_ kind: ServiceKind) -> String? {
        switch kind {
        case .redis:    return "bin/redis-server"
        case .postgres: return "bin/postgres"
        case .mysql:    return "bin/mysqld"
        default:        return nil
        }
    }

    /// Newest installed version of `kind` (a version dir whose marker executable exists), or nil.
    public func installedVersion(_ kind: ServiceKind) -> String? {
        guard let marker = Self.marker(kind) else { return nil }
        let root = paths.runtimeLangRoot(kind.rawValue)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else { return nil }
        return entries
            .filter { fm.isExecutableFile(atPath: root.appendingPathComponent($0).appendingPathComponent(marker).path) }
            // Numeric compare so "7.10" > "7.9" and "10.0" > "9.0" (lexicographic would mis-order).
            .max { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    public func isInstalled(_ kind: ServiceKind) -> Bool { installedVersion(kind) != nil }

    /// Resolve an executable inside the installed version's tree (e.g. `bin/redis-server`, `bin/initdb`).
    public func binary(_ kind: ServiceKind, _ relPath: String) -> URL? {
        guard let version = installedVersion(kind) else { return nil }
        return paths.runtimeDir(kind.rawValue, version).appendingPathComponent(relPath)
    }

    /// The release a user could install for `kind` (a manifest entry, when not already installed).
    public func availableRelease(_ kind: ServiceKind) -> ServiceBinaryRelease? {
        guard !isInstalled(kind) else { return nil }
        return Self.manifest.first { $0.kind == kind }
    }

    /// Destination dir for installing a release (`runtimes/<kind>/<version>`).
    public func installDir(_ release: ServiceBinaryRelease) -> URL {
        paths.runtimeDir(release.kind.rawValue, release.version)
    }
}
