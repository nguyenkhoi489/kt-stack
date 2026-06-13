import Foundation

/// Copies the bundled, relocatable service binaries (nginx, dnsmasq, mkcert, mailpit) out of the
/// immutable signed app bundle into the writable app-support `bin/` directory on first run, and
/// re-stages them when the bundle ships newer copies. PHP is NOT bundled — it installs on demand —
/// so the PHP staging path here is a guarded no-op unless a build drops PHP into `Resources/bin`.
///
/// The signed `.app` is read-only, so the runtime CANNOT execute binaries in place — they
/// must live in a writable tree. Every binary's code signature is verified BEFORE it is
/// copied and AFTER it lands, as a defence against a tampered app-support directory: an
/// attacker who swapped `php-fpm` for a trojan would fail the post-stage `codesign` check
/// and the launch is aborted.
public struct BinaryStager {
    public enum StageError: LocalizedError {
        case missingSource(String)
        case signatureInvalid(String)
        case copyFailed(String, String)

        public var errorDescription: String? {
            switch self {
            case .missingSource(let p):   return "Bundled binary not found: \(p)"
            case .signatureInvalid(let p): return "Code signature check failed for \(p) — refusing to run a possibly tampered binary."
            case .copyFailed(let n, let m): return "Could not stage \(n): \(m)"
            }
        }
    }

    /// Core binaries REQUIRED in `bin/` — a missing one aborts startup. `dnsmasq` is bundled for DNS
    /// automation (the sudo-fallback / helper copies it to a root-owned location) and staged here too
    /// for signature verification. PHP is NOT here — it is staged into the runtimes layout (below).
    public static let binBinaries = ["nginx", "dnsmasq", "mkcert"]

    /// Binaries staged into `bin/` ONLY when present in the bundle. Mailpit is the one bundled mail
    /// catcher (baseline). The database engines (MySQL/PostgreSQL/Redis) are NOT bundled — they
    /// install on demand via the Services UI into `runtimes/<engine>/` (see `ServiceBinaryCatalog`),
    /// so KDWarm ships lean.
    public static let optionalBinaryNames = ["mailpit"]

    private let bundleBinDir: URL
    private let paths: AppSupportPaths
    private let fileManager: FileManager

    public init(bundleBinDir: URL, paths: AppSupportPaths, fileManager: FileManager = .default) {
        self.bundleBinDir = bundleBinDir
        self.paths = paths
        self.fileManager = fileManager
    }

    /// Stage any binary that is missing or out of date. Verifies signatures on both ends. Required
    /// `bin/` binaries must be present; PHP runtimes + optional DB/Mailpit binaries stage if bundled.
    public func stageIfNeeded() throws {
        try paths.ensureDirectoryTree(fileManager: fileManager)
        for name in Self.binBinaries {
            try stage(from: bundleBinDir.appendingPathComponent(name),
                      to: paths.bin.appendingPathComponent(name), displayName: name)
        }
        try stagePHPRuntimes()
        for name in Self.optionalBinaryNames where fileManager.isReadableFile(
            atPath: bundleBinDir.appendingPathComponent(name).path) {
            try stage(from: bundleBinDir.appendingPathComponent(name),
                      to: paths.bin.appendingPathComponent(name), displayName: name)
        }
    }

    /// Stage any bundled PHP into the runtimes layout (`runtimes/php/<version>/bin/{php,php-fpm}`).
    /// PHP now installs on demand (nothing ships in the bundle), so these are no-ops unless a build is
    /// configured to drop PHP into `Resources/bin` — kept as a guarded, presence-checked fallback.
    private func stagePHPRuntimes() throws {
        // Default version from a flat php/php-fpm, only if a build placed one in the bundle.
        if fileManager.isReadableFile(atPath: bundleBinDir.appendingPathComponent("php-fpm").path) {
            try stagePHPVersion(BundledPHP.defaultVersion, fpmSource: "php-fpm", cliSource: "php")
        }
        // Optional extra versions from the build pipeline (e.g. php-fpm-8.1 → runtimes/php/8.1/bin).
        for version in BundledPHP.plannedVersions where version != BundledPHP.defaultVersion {
            let fpm = "php-fpm-\(version)"
            guard fileManager.isReadableFile(atPath: bundleBinDir.appendingPathComponent(fpm).path) else { continue }
            try stagePHPVersion(version, fpmSource: fpm, cliSource: "php-\(version)")
        }
    }

    private func stagePHPVersion(_ version: String, fpmSource: String, cliSource: String) throws {
        let binDir = paths.runtimeBin("php", version)
        try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        try stage(from: bundleBinDir.appendingPathComponent(fpmSource),
                  to: binDir.appendingPathComponent("php-fpm"), displayName: fpmSource)
        // The matching CLI is best-effort (a pool only needs php-fpm); stage it if bundled.
        let cli = bundleBinDir.appendingPathComponent(cliSource)
        if fileManager.isReadableFile(atPath: cli.path) {
            try stage(from: cli, to: binDir.appendingPathComponent("php"), displayName: cliSource)
        }
    }

    private func stage(from source: URL, to dest: URL, displayName name: String) throws {
        guard fileManager.isReadableFile(atPath: source.path) else {
            throw StageError.missingSource(source.path)
        }
        guard Self.verifySignature(at: source) else {
            throw StageError.signatureInvalid(source.path)
        }

        if try shouldRestage(source: source, dest: dest) {
            do {
                if fileManager.fileExists(atPath: dest.path) {
                    try fileManager.removeItem(at: dest)
                }
                try fileManager.copyItem(at: source, to: dest)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
            } catch {
                throw StageError.copyFailed(name, error.localizedDescription)
            }
        }

        guard Self.verifySignature(at: dest) else {
            throw StageError.signatureInvalid(dest.path)
        }
    }

    /// Re-stage when the destination is absent or differs from the bundle copy (size or mtime).
    private func shouldRestage(source: URL, dest: URL) throws -> Bool {
        guard fileManager.fileExists(atPath: dest.path) else { return true }
        let s = try fileManager.attributesOfItem(atPath: source.path)
        let d = try fileManager.attributesOfItem(atPath: dest.path)
        let sSize = (s[.size] as? Int) ?? -1
        let dSize = (d[.size] as? Int) ?? -2
        if sSize != dSize { return true }
        let sDate = (s[.modificationDate] as? Date) ?? .distantFuture
        let dDate = (d[.modificationDate] as? Date) ?? .distantPast
        return sDate > dDate
    }

    /// `codesign --verify --strict`. Ad-hoc signatures (dev builds) pass and still seal the
    /// code, so post-stage tampering is detected.
    static func verifySignature(at url: URL) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        proc.arguments = ["--verify", "--strict", url.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }
}
