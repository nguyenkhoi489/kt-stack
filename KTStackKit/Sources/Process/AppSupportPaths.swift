import Foundation

public struct AppSupportPaths: Sendable {
    public let root: URL

  
    public init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.root = base.appendingPathComponent("KTStack", isDirectory: true)
    }

    public init(root: URL) { self.root = root }

    // MARK: Directories

    public var bin: URL              { dir("bin") }
    public var shimBinDir: URL       { dir("shims") }
    public var runtimes: URL         { dir("runtimes") }          // Phase 7
    public var tools: URL            { dir("tools") }
    public var config: URL           { dir("config") }
    public var nginxConfigDir: URL   { config.appendingPathComponent("nginx", isDirectory: true) }
    public var sitesEnabled: URL     { nginxConfigDir.appendingPathComponent("sites-enabled", isDirectory: true) }
    public var phpFpmConfigDir: URL  { config.appendingPathComponent("php-fpm", isDirectory: true) }
   
    public var phpConfigDir: URL     { config.appendingPathComponent("php", isDirectory: true) }
  
    public var sitesConfigDir: URL   { config.appendingPathComponent("sites", isDirectory: true) }
   
    public var caDir: URL            { config.appendingPathComponent("ca", isDirectory: true) }
  
    public var certsDir: URL         { config.appendingPathComponent("certs", isDirectory: true) }
    public var run: URL              { dir("run") }
    public var logs: URL             { dir("logs") }
    public var sites: URL            { dir("sites") }
  
    public var data: URL             { dir("data") }

    public var launchAgents: URL     { dir("launchd") }

    public var backups: URL          { dir("backups") }

    public var sitesRegistryFile: URL { sitesConfigDir.appendingPathComponent("sites.json") }

   
    public static var defaultSitesRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Sites/WWW", isDirectory: true)
    }

    public var allDirectories: [URL] {
        [root, bin, runtimes, tools, config, nginxConfigDir, sitesEnabled, phpFpmConfigDir, phpConfigDir,
         sitesConfigDir, caDir, certsDir, run, logs, logsSites, sites, data, launchAgents, backups]
    }

    // MARK: Per-service data / config / logs (databases + Mailpit)

    public func serviceData(_ service: String) -> URL {
        data.appendingPathComponent(service, isDirectory: true)
    }

    public func serviceConfig(_ service: String, ext: String = "conf") -> URL {
        config.appendingPathComponent("\(service).\(ext)")
    }
  
    public func serviceLog(_ service: String) -> URL {
        logs.appendingPathComponent("\(service).log")
    }

    public func serviceSocket(_ service: String) -> URL {
        run.appendingPathComponent("\(service).sock")
    }
  
    public func launchAgentPlist(_ label: String) -> URL {
        launchAgents.appendingPathComponent("\(label).plist")
    }

    public func tunnelLabel(_ siteID: String) -> String { "com.ktstack.tunnel.\(siteID)" }
    public func tunnelLog(_ siteID: String) -> URL {
        logs.appendingPathComponent("tunnel-\(siteID).log")
    }

    public func binary(_ name: String) -> URL { bin.appendingPathComponent(name) }

    // MARK: Binaries (staged copies)

    public var nginxBinary: URL  { bin.appendingPathComponent("nginx") }
    public var mkcertBinary: URL { bin.appendingPathComponent("mkcert") }

    // MARK: Runtimes layout (runtimes/<lang>/<version>/bin/…)

    public func runtimeLangRoot(_ lang: String) -> URL {
        runtimes.appendingPathComponent(lang, isDirectory: true)
    }
    public func runtimeDir(_ lang: String, _ version: String) -> URL {
        runtimeLangRoot(lang).appendingPathComponent(version, isDirectory: true)
    }
    
    public func runtimeBin(_ lang: String, _ version: String) -> URL {
        runtimeDir(lang, version).appendingPathComponent("bin", isDirectory: true)
    }

    public var backupManifest: URL { backups.appendingPathComponent("manifest.json") }
    public var queryHistoryFile: URL { config.appendingPathComponent("query-history.json") }

    public func backupSetDir(_ id: UUID) -> URL {
        backups.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func toolsDir(_ name: String) -> URL {
        tools.appendingPathComponent(name, isDirectory: true)
    }

    public func toolVersionDir(_ name: String, _ version: String) -> URL {
        toolsDir(name).appendingPathComponent(version, isDirectory: true)
    }

    public var composerPhar: URL { toolsDir("composer").appendingPathComponent("composer.phar") }
    public var wpCliPhar: URL    { toolsDir("wp-cli").appendingPathComponent("wp-cli.phar") }

    public var dumpsPrependFile: URL { config.appendingPathComponent("php-vardumper-prepend.php") }


    public var phpRuntimesRoot: URL { runtimeLangRoot("php") }
    public func phpFpmBinary(version: String) -> URL {
        runtimeBin("php", version).appendingPathComponent("php-fpm")
    }
    public func phpBinary(version: String) -> URL {
        runtimeBin("php", version).appendingPathComponent("php")
    }

 
    public func phpModulesDir(version: String) -> URL {
        runtimeDir("php", version).appendingPathComponent("modules", isDirectory: true)
    }
 
    public func phpExtConfDir(version: String) -> URL {
        runtimeDir("php", version).appendingPathComponent("conf.d", isDirectory: true)
    }

    // MARK: TLS material

    public var caRootCert: URL { caDir.appendingPathComponent("rootCA.pem") }
    public var caRootKey: URL  { caDir.appendingPathComponent("rootCA-key.pem") }
    public var catchAllCert: URL { caDir.appendingPathComponent("catchall-cert.pem") }
    public var catchAllKey: URL  { caDir.appendingPathComponent("catchall-key.pem") }
    public func siteCertDir(_ name: String) -> URL { certsDir.appendingPathComponent(name, isDirectory: true) }
    public func siteCert(_ name: String) -> URL { siteCertDir(name).appendingPathComponent("cert.pem") }
    public func siteKey(_ name: String) -> URL { siteCertDir(name).appendingPathComponent("key.pem") }

    // MARK: Well-known files

    public var nginxConf: URL    { nginxConfigDir.appendingPathComponent("nginx.conf") }
    public var nginxPid: URL     { run.appendingPathComponent("nginx.pid") }
    public var nginxErrorLog: URL  { logs.appendingPathComponent("nginx-error.log") }
    public var nginxAccessLog: URL { logs.appendingPathComponent("nginx-access.log") }


    public var logsSites: URL { logs.appendingPathComponent("sites", isDirectory: true) }
    public func siteAccessLog(_ domain: String) -> URL { logsSites.appendingPathComponent("\(domain).access.log") }
    public func siteErrorLog(_ domain: String) -> URL { logsSites.appendingPathComponent("\(domain).error.log") }

    public func nodeOutLog(_ domain: String) -> URL { logsSites.appendingPathComponent("node-\(domain).out.log") }
    public func nodeErrLog(_ domain: String) -> URL { logsSites.appendingPathComponent("node-\(domain).err.log") }

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

    public func phpIniDir(version: String) -> URL {
        phpConfigDir.appendingPathComponent(version, isDirectory: true)
    }

    public func phpIni(version: String) -> URL {
        phpIniDir(version: version).appendingPathComponent("php.ini")
    }

    private func dir(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }

    public func ensureDirectoryTree(fileManager: FileManager = .default) throws {
        for url in allDirectories {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
    }
}
