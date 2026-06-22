import Foundation
import Combine

public struct SiteRemovalCoordinator: Sendable {
    private let deleteFolder: @Sendable (Site) async throws -> Void
    private let dropDatabase: @Sendable (String) async throws -> Void
    private let removeRecord: @Sendable (Site) async -> Void

    public init(deleteFolder: @escaping @Sendable (Site) async throws -> Void,
                dropDatabase: @escaping @Sendable (String) async throws -> Void,
                removeRecord: @escaping @Sendable (Site) async -> Void) {
        self.deleteFolder = deleteFolder
        self.dropDatabase = dropDatabase
        self.removeRecord = removeRecord
    }

    public func remove(_ site: Site) async throws {
        try await deleteFolder(site)
        if let databaseName = site.databaseName {
            try await dropDatabase(databaseName)
        }
        await removeRecord(site)
    }
}

@MainActor
public final class SiteRegistry: ObservableObject {
    @Published public private(set) var sites: [Site] = []

    /// Fired after any successful mutation (and after load), on the main actor.
    public var onChange: (() -> Void)?

    /// The single dev TLD this registry validates against (dnsmasq wildcard). Injected from
    /// `AppPreferences` at init and baked for the registry's lifetime — a change takes effect on the
    /// next launch (the registry/helper read the TLD once at startup; live re-injection is avoided).
    public let tld: String

    private let storeURL: URL
    private let inspector = SiteInspector()
    private let versionResolver = ProjectVersionResolver()

    private let installedPHP: @Sendable () -> [String]

    public init(storeURL: URL,
                tld: String = AppPreferences.defaultTLD,
                installedPHP: @escaping @Sendable () -> [String] = { BundledPHP.plannedVersions }) {
        self.storeURL = storeURL
        self.tld = tld
        self.installedPHP = installedPHP
        load()
    }

    public enum RegistryError: LocalizedError, Equatable {
        case invalidDomain(String)
        case wrongTLD(String, expected: String)
        case domainTaken(String)
        case notADirectory(String)
        case unsafeDeletePath(String)

        public var errorDescription: String? {
            switch self {
            case .invalidDomain(let d): return "“\(d)” is not a valid domain."
            case .wrongTLD(let d, let t): return "“\(d)” must end in .\(t) (MVP resolves only .\(t) automatically)."
            case .domainTaken(let d):   return "Another site already uses “\(d)”."
            case .notADirectory(let p): return "“\(p)” is not a folder."
            case .unsafeDeletePath(let p): return "Refusing to delete unsafe site folder “\(p)”."
            }
        }
    }

    // MARK: - Mutators

    @discardableResult
    public func add(folder: URL, phpVersion: String = BundledPHP.defaultVersion,
                    respectProjectMarkers: Bool = true,
                    databaseName: String? = nil) throws -> Site {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw RegistryError.notADirectory(folder.path)
        }
        let info = inspector.inspect(folder: folder, tld: tld)
        let domain = uniqueDomain(info.defaultDomain)

        let resolvedPHP = respectProjectMarkers
            ? resolveInitialPHP(folder: folder, fallback: phpVersion)
            : (knownPHPVersions().contains(phpVersion) ? phpVersion : (knownPHPVersions().first ?? BundledPHP.defaultVersion))
        let site = Site(name: folder.lastPathComponent,
                        path: folder.path,
                        docroot: info.docroot.path,
                        domain: domain,
                        phpVersion: resolvedPHP,
                        type: info.type,
                        databaseName: databaseName)
        sites.append(site)
        persist()
        return site
    }

    public func remove(_ site: Site) {
        sites.removeAll { $0.id == site.id }
        persist()
    }

    public func removeDeletingFolder(_ site: Site) throws {
        try deleteFolderForRemoval(site)
        remove(site)
    }

    public func validateCanRemoveDeletingFolder(_ site: Site) throws {
        let folder = URL(fileURLWithPath: site.path, isDirectory: true).standardizedFileURL
        try validateDeletableSiteFolder(folder)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) else { return }
        guard isDirectory.boolValue else { throw RegistryError.notADirectory(folder.path) }
    }

    public func deleteFolderForRemoval(_ site: Site) throws {
        let folder = URL(fileURLWithPath: site.path, isDirectory: true).standardizedFileURL
        try validateCanRemoveDeletingFolder(site)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    public func editDomain(_ site: Site, to newDomain: String) throws {
        let domain = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
        try validateDomain(domain, excluding: site.id)
        update(site.id) { $0.domain = domain }
    }

    public func setPHPVersion(_ site: Site, to version: String) {
        guard knownPHPVersions().contains(version) else { return }
        update(site.id) { $0.phpVersion = version }
    }

    private func knownPHPVersions() -> [String] {
        let installed = installedPHP()
        return installed.isEmpty ? [BundledPHP.defaultVersion] : installed
    }

    private func resolveInitialPHP(folder: URL, fallback: String) -> String {
        let known = knownPHPVersions()
        return versionResolver.selectVersion(.php, forProjectAt: folder, installed: known, preferred: fallback)
            ?? (known.first ?? BundledPHP.defaultVersion)
    }

  
    public func setSecure(_ site: Site, _ secure: Bool) {
        update(site.id) { $0.secure = secure }
    }

    public func setNodeCommand(_ site: Site, _ command: String?) {
        let trimmed = command?.trimmingCharacters(in: .whitespacesAndNewlines)
        update(site.id) { $0.nodeCommand = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }

    public func setNodeEnabled(_ site: Site, _ enabled: Bool, port: Int?) {
        update(site.id) {
            $0.nodeEnabled = enabled
            if enabled, $0.nodePort == nil, let port { $0.nodePort = port }
        }
    }

    public func reinspect(_ site: Site) {
        let info = inspector.inspect(folder: URL(fileURLWithPath: site.path), tld: tld)
        guard info.docroot.path != site.docroot || info.type != site.type else { return }
        update(site.id) { $0.docroot = info.docroot.path; $0.type = info.type }
    }

    // MARK: - Validation

    public func validateDomain(_ domain: String, excluding id: UUID? = nil) throws {
        guard NginxConfigWriter.isValidDomain(domain) else { throw RegistryError.invalidDomain(domain) }
        guard domain.hasSuffix(".\(tld)"), domain.count > tld.count + 1 else {
            throw RegistryError.wrongTLD(domain, expected: tld)
        }
        if sites.contains(where: { $0.domain == domain && $0.id != id }) {
            throw RegistryError.domainTaken(domain)
        }
    }

    // MARK: - Private

    private func update(_ id: UUID, _ mutate: (inout Site) -> Void) {
        guard let idx = sites.firstIndex(where: { $0.id == id }) else { return }
        mutate(&sites[idx])
        persist()
    }

    private func validateDeletableSiteFolder(_ folder: URL) throws {
        let path = folder.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard path != "/", path != home, !folder.lastPathComponent.isEmpty else {
            throw RegistryError.unsafeDeletePath(path)
        }
    }

    private func uniqueDomain(_ base: String) -> String {
        guard sites.contains(where: { $0.domain == base }) else { return base }
        // base = "<label>.test" → insert "-N" before the TLD.
        let label = base.replacingOccurrences(of: ".\(tld)", with: "")
        var n = 2
        while sites.contains(where: { $0.domain == "\(label)-\(n).\(tld)" }) { n += 1 }
        return "\(label)-\(n).\(tld)"
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }   // absent file → fresh
        if let decoded = try? JSONDecoder().decode([Site].self, from: data) {
            sites = decoded
        } else {
          
            let backup = storeURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: storeURL, to: backup)
            NSLog("KTStack: could not decode site registry; backed up to \(backup.lastPathComponent)")
        }
        onChange?()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(sites)
            try data.write(to: storeURL, options: .atomic)
        } catch {
           
            NSLog("KTStack: failed to persist site registry: \(error.localizedDescription)")
        }
        onChange?()
    }
}
