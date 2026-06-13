import Foundation

/// Canonical filesystem layout under `~/Library/Application Support/KDWarm`.
///
/// Single source of truth for every directory the runtime touches (bin, config, run,
/// logs, sites). Established here in the first HTTP slice and reused by all later phases.
/// The signed app bundle is immutable, so binaries are staged into this writable tree and
/// run from here — never from inside `KDWarm.app`.
public struct AppSupportPaths: Sendable {
    public let root: URL

    /// Default location: the user's Application Support directory + `KDWarm`.
    public init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.root = base.appendingPathComponent("KDWarm", isDirectory: true)
    }

    /// Explicit root — used by tests to stage the tree in a temp dir.
    public init(root: URL) { self.root = root }

    // MARK: Directories

    public var bin: URL              { dir("bin") }
    public var runtimes: URL         { dir("runtimes") }          // Phase 7
    public var config: URL           { dir("config") }
    public var nginxConfigDir: URL   { config.appendingPathComponent("nginx", isDirectory: true) }
    public var sitesEnabled: URL     { nginxConfigDir.appendingPathComponent("sites-enabled", isDirectory: true) }
    public var phpFpmConfigDir: URL  { config.appendingPathComponent("php-fpm", isDirectory: true) }
    /// Root for the managed, user-editable `php.ini` files, one subdir per PHP version
    /// (`config/php/<version>/php.ini`). php-fpm reads its version's file via `-c`.
    public var phpConfigDir: URL     { config.appendingPathComponent("php", isDirectory: true) }
    /// Holds the persisted site registry (`sites.json`).
    public var sitesConfigDir: URL   { config.appendingPathComponent("sites", isDirectory: true) }
    /// mkcert CAROOT — the local root CA material (key is 600, never leaves this dir).
    public var caDir: URL            { config.appendingPathComponent("ca", isDirectory: true) }
    /// Per-site TLS leaf certs (`certs/<name>/{cert,key}.pem`).
    public var certsDir: URL         { config.appendingPathComponent("certs", isDirectory: true) }
    public var run: URL              { dir("run") }
    public var logs: URL             { dir("logs") }
    public var sites: URL            { dir("sites") }
    /// Persistent data directories for bundled databases / Mailpit (`data/mysql`, `data/postgres`,
    /// `data/redis`, `data/mailpit`). Never inside the immutable bundle — always app-support.
    public var data: URL             { dir("data") }
    /// Rendered LaunchAgent plists (loaded via `launchctl bootstrap`). Kept out of
    /// `~/Library/LaunchAgents` so they are app-controlled, not auto-loaded at login.
    public var launchAgents: URL     { dir("launchd") }

    /// Persisted registry of explicitly-added sites.
    public var sitesRegistryFile: URL { sitesConfigDir.appendingPathComponent("sites.json") }

    /// Default browse root for "Add Site" (`~/Sites/WWW`). Any folder is allowed; this is just
    /// the suggested location.
    public static var defaultSitesRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Sites/WWW", isDirectory: true)
    }

    /// Every directory that `ensureDirectoryTree()` creates.
    public var allDirectories: [URL] {
        [root, bin, runtimes, config, nginxConfigDir, sitesEnabled, phpFpmConfigDir, phpConfigDir,
         sitesConfigDir, caDir, certsDir, run, logs, logsSites, sites, data, launchAgents]
    }

    // MARK: Per-service data / config / logs (databases + Mailpit)

    /// Persistent data dir for a service (`data/<service>`), e.g. a DB datadir.
    public func serviceData(_ service: String) -> URL {
        data.appendingPathComponent(service, isDirectory: true)
    }
    /// Rendered config file for a service (`config/<service>.conf`).
    public func serviceConfig(_ service: String, ext: String = "conf") -> URL {
        config.appendingPathComponent("\(service).\(ext)")
    }
    /// Combined stdout+stderr log for a service (`logs/<service>.log`).
    public func serviceLog(_ service: String) -> URL {
        logs.appendingPathComponent("\(service).log")
    }
    /// Unix socket for a service that uses one (`run/<service>.sock`).
    public func serviceSocket(_ service: String) -> URL {
        run.appendingPathComponent("\(service).sock")
    }
    /// Rendered LaunchAgent plist for a launchd label (`launchd/<label>.plist`).
    public func launchAgentPlist(_ label: String) -> URL {
        launchAgents.appendingPathComponent("\(label).plist")
    }

    /// Staged binary for a bundled service executable (`bin/<name>`).
    public func binary(_ name: String) -> URL { bin.appendingPathComponent(name) }

    // MARK: Binaries (staged copies)

    public var nginxBinary: URL  { bin.appendingPathComponent("nginx") }
    public var mkcertBinary: URL { bin.appendingPathComponent("mkcert") }

    // MARK: Runtimes layout (runtimes/<lang>/<version>/bin/…)

    /// Root for a language's installed versions (`runtimes/<lang>`).
    public func runtimeLangRoot(_ lang: String) -> URL {
        runtimes.appendingPathComponent(lang, isDirectory: true)
    }
    /// A specific installed runtime version dir (`runtimes/<lang>/<version>`).
    public func runtimeDir(_ lang: String, _ version: String) -> URL {
        runtimeLangRoot(lang).appendingPathComponent(version, isDirectory: true)
    }
    /// Executable dir for an installed runtime version (`runtimes/<lang>/<version>/bin`).
    public func runtimeBin(_ lang: String, _ version: String) -> URL {
        runtimeDir(lang, version).appendingPathComponent("bin", isDirectory: true)
    }

    /// PHP runtimes live under `runtimes/php/<version>/bin/{php,php-fpm}` — each version is a
    /// self-contained static build (no shared lib tree), so pools execute the per-version binary.
    public var phpRuntimesRoot: URL { runtimeLangRoot("php") }
    public func phpFpmBinary(version: String) -> URL {
        runtimeBin("php", version).appendingPathComponent("php-fpm")
    }
    public func phpBinary(version: String) -> URL {
        runtimeBin("php", version).appendingPathComponent("php")
    }

    /// Managed optional-extension `.so` dir for a PHP version (`runtimes/php/<version>/modules`). Lives
    /// inside the version's runtime tree so a version-uninstall (removing the tree) tears it down too.
    public func phpModulesDir(version: String) -> URL {
        runtimeDir("php", version).appendingPathComponent("modules", isDirectory: true)
    }
    /// Scan-dir of per-extension inis for a PHP version (`runtimes/php/<version>/conf.d`). php-fpm/php
    /// is pointed here via `PHP_INI_SCAN_DIR`; files load in ascending name order (00- before 20-).
    public func phpExtConfDir(version: String) -> URL {
        runtimeDir("php", version).appendingPathComponent("conf.d", isDirectory: true)
    }

    // MARK: TLS material

    public var caRootCert: URL { caDir.appendingPathComponent("rootCA.pem") }
    public var caRootKey: URL  { caDir.appendingPathComponent("rootCA-key.pem") }
    public func siteCertDir(_ name: String) -> URL { certsDir.appendingPathComponent(name, isDirectory: true) }
    public func siteCert(_ name: String) -> URL { siteCertDir(name).appendingPathComponent("cert.pem") }
    public func siteKey(_ name: String) -> URL { siteCertDir(name).appendingPathComponent("key.pem") }

    // MARK: Well-known files

    public var nginxConf: URL    { nginxConfigDir.appendingPathComponent("nginx.conf") }
    public var nginxPid: URL     { run.appendingPathComponent("nginx.pid") }
    public var nginxErrorLog: URL  { logs.appendingPathComponent("nginx-error.log") }
    public var nginxAccessLog: URL { logs.appendingPathComponent("nginx-access.log") }

    /// Per-site nginx logs live under `logs/sites/<domain>.{access,error}.log` so the Logs viewer
    /// can tail one site in isolation (the vhost writer emits these per server block).
    public var logsSites: URL { logs.appendingPathComponent("sites", isDirectory: true) }
    public func siteAccessLog(_ domain: String) -> URL { logsSites.appendingPathComponent("\(domain).access.log") }
    public func siteErrorLog(_ domain: String) -> URL { logsSites.appendingPathComponent("\(domain).error.log") }

    public func vhost(_ name: String) -> URL {
        sitesEnabled.appendingPathComponent("\(name).conf")
    }
    public func phpFpmPool(_ name: String) -> URL {
        phpFpmConfigDir.appendingPathComponent("\(name).conf")
    }
    public func phpFpmSocket(_ name: String) -> URL {
        run.appendingPathComponent("php-fpm-\(name).sock")
    }
    public func phpFpmPid(_ name: String) -> URL {
        run.appendingPathComponent("php-fpm-\(name).pid")
    }
    public func phpFpmLog(_ name: String) -> URL {
        logs.appendingPathComponent("php-fpm-\(name).log")
    }

    /// Per-version config dir holding the managed `php.ini` (`config/php/<version>`). Created on
    /// demand when the ini is first seeded (not part of `ensureDirectoryTree`, which is version-agnostic).
    public func phpIniDir(version: String) -> URL {
        phpConfigDir.appendingPathComponent(version, isDirectory: true)
    }
    /// The managed, user-editable `php.ini` for a PHP version (`config/php/<version>/php.ini`).
    public func phpIni(version: String) -> URL {
        phpIniDir(version: version).appendingPathComponent("php.ini")
    }

    private func dir(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }

    /// Create the full tree on first run, restricting each dir to the owning user (0700)
    /// so no other local account can drop a tampered binary or read site state.
    public func ensureDirectoryTree(fileManager: FileManager = .default) throws {
        for url in allDirectories {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
    }
}
