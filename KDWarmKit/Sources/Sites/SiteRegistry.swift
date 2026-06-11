import Foundation
import Combine

/// Source of truth for the set of explicitly-added sites. Persists to `config/sites/sites.json`.
/// There is NO background scan of `~/Sites/WWW` — sites enter only via `add(folder:)`.
///
/// Mutators validate the editable domain (must be a valid hostname ending in a wildcarded TLD,
/// `.test` in MVP) and enforce domain uniqueness, then persist and fire `onChange` so the
/// orchestrator can regenerate vhosts / reconcile pools / reload nginx.
@MainActor
public final class SiteRegistry: ObservableObject {
    @Published public private(set) var sites: [Site] = []

    /// Fired after any successful mutation (and after load), on the main actor.
    public var onChange: (() -> Void)?

    /// MVP resolves only this TLD automatically (dnsmasq wildcard, Phase 4).
    public let tld = "test"

    private let storeURL: URL
    private let inspector = SiteInspector()
    private let versionResolver = VersionResolver()
    /// Supplies the PHP versions actually installed (runnable). The registry clamps every site's
    /// version to this set so a project marker or disk edit can't point a site at a phantom pool
    /// (which nginx would `fastcgi_pass` to a socket that never appears → 502). Defaults to the
    /// planned set for tests; the app injects the live installed set from the runtimes layout.
    private let installedPHP: @Sendable () -> [String]

    public init(storeURL: URL,
                installedPHP: @escaping @Sendable () -> [String] = { BundledPHP.plannedVersions }) {
        self.storeURL = storeURL
        self.installedPHP = installedPHP
        load()
    }

    public enum RegistryError: LocalizedError, Equatable {
        case invalidDomain(String)
        case wrongTLD(String, expected: String)
        case domainTaken(String)
        case notADirectory(String)

        public var errorDescription: String? {
            switch self {
            case .invalidDomain(let d): return "“\(d)” is not a valid domain."
            case .wrongTLD(let d, let t): return "“\(d)” must end in .\(t) (MVP resolves only .\(t) automatically)."
            case .domainTaken(let d):   return "Another site already uses “\(d)”."
            case .notADirectory(let p): return "“\(p)” is not a folder."
            }
        }
    }

    // MARK: - Mutators

    /// Register a folder. Inspects it for docroot/type/default-domain, ensures the domain is
    /// unique (suffixes `-2`, `-3`… on collision), and persists.
    @discardableResult
    public func add(folder: URL, phpVersion: String = BundledPHP.defaultVersion) throws -> Site {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw RegistryError.notADirectory(folder.path)
        }
        let info = inspector.inspect(folder: folder, tld: tld)
        let domain = uniqueDomain(info.defaultDomain)
        // Source the PHP version from a project marker (.kdwarmrc / .php-version) when present, so a
        // repo that pins its version is honored on add — but clamp to an INSTALLED version (markers
        // are untrusted; an uninstalled pin would route to a pool that never starts).
        let resolvedPHP = resolveInitialPHP(folder: folder, fallback: phpVersion)
        let site = Site(name: folder.lastPathComponent,
                        path: folder.path,
                        docroot: info.docroot.path,
                        domain: domain,
                        phpVersion: resolvedPHP,
                        type: info.type)
        sites.append(site)
        persist()
        return site
    }

    public func remove(_ site: Site) {
        sites.removeAll { $0.id == site.id }
        persist()
    }

    /// Change a site's domain. Validates hostname + TLD + uniqueness before applying.
    public func editDomain(_ site: Site, to newDomain: String) throws {
        let domain = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
        try validateDomain(domain, excluding: site.id)
        update(site.id) { $0.domain = domain }
    }

    /// Set a site's PHP version. The registry is the trust boundary (sites.json is editable on
    /// disk), so reject anything outside the INSTALLED set rather than routing to a phantom pool.
    public func setPHPVersion(_ site: Site, to version: String) {
        guard knownPHPVersions().contains(version) else { return }
        update(site.id) { $0.phpVersion = version }
    }

    /// The PHP versions a site may use: the installed set, or the bundled default before staging.
    private func knownPHPVersions() -> [String] {
        let installed = installedPHP()
        return installed.isEmpty ? [BundledPHP.defaultVersion] : installed
    }

    /// Marker version (clamped to installed) → caller fallback (clamped) → first installed/default.
    private func resolveInitialPHP(folder: URL, fallback: String) -> String {
        let known = knownPHPVersions()
        if let marker = versionResolver.version(.php, forProjectAt: folder), known.contains(marker) {
            return marker
        }
        return known.contains(fallback) ? fallback : (known.first ?? BundledPHP.defaultVersion)
    }

    /// Flip a site's secure (HTTPS) flag. Cert minting + trust is handled by the orchestrator
    /// BEFORE this is set, so the config generator sees the leaf when it regenerates.
    public func setSecure(_ site: Site, _ secure: Bool) {
        update(site.id) { $0.secure = secure }
    }

    /// Re-inspect a registered folder (docroot/type may have changed) without touching its
    /// editable domain or PHP version. Used by the folder watcher. No-op (no persist, no reload)
    /// when nothing changed, so editor save-storms don't churn the registry.
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
            // Present but undecodable (corrupt / old schema): back it up so the next persist
            // doesn't silently overwrite it, and log rather than vanish the user's sites.
            let backup = storeURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: storeURL, to: backup)
            NSLog("KDWarm: could not decode site registry; backed up to \(backup.lastPathComponent)")
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
            // Persistence failure is non-fatal to the in-memory state; surface via logs only.
            NSLog("KDWarm: failed to persist site registry: \(error.localizedDescription)")
        }
        onChange?()
    }
}
