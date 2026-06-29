import Foundation

enum ServiceDataRelocation {
    private static let dbCacheKinds: [(kind: ServiceKind, service: String)] = [
        (.mysql, "mysql"),
        (.postgres, "postgres"),
        (.redis, "redis"),
        (.mongodb, "mongodb"),
    ]

    static func runIfNeeded(paths: AppSupportPaths, catalog: ServiceBinaryCatalog) {
        for (kind, service) in dbCacheKinds {
            relocate(kind: kind, service: service, paths: paths, catalog: catalog)
        }
    }

    private static func relocate(
        kind: ServiceKind,
        service: String,
        paths: AppSupportPaths,
        catalog: ServiceBinaryCatalog
    ) {
        let fm = FileManager.default
        let flatDir = paths.serviceData(service)
        let migratingDir = paths.data.appendingPathComponent("\(service).migrating", isDirectory: true)

        if fm.fileExists(atPath: migratingDir.path) {
            finishFromMigrating(
                migratingDir: migratingDir,
                flatDir: flatDir,
                kind: kind,
                service: service,
                paths: paths,
                catalog: catalog
            )
            return
        }

        guard fm.fileExists(atPath: flatDir.path),
              hasDataMarker(at: flatDir, for: kind) else { return }

        guard let version = latestInstalled(kind, catalog: catalog) else { return }
        let versionedDir = paths.serviceData(service, version: version)
        guard !fm.fileExists(atPath: versionedDir.path) else { return }

        do {
            try fm.moveItem(at: flatDir, to: migratingDir)
            try fm.createDirectory(at: flatDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.moveItem(at: migratingDir, to: versionedDir)
        } catch {}
    }

    private static func finishFromMigrating(
        migratingDir: URL,
        flatDir: URL,
        kind: ServiceKind,
        service: String,
        paths: AppSupportPaths,
        catalog: ServiceBinaryCatalog
    ) {
        let fm = FileManager.default
        guard let version = latestInstalled(kind, catalog: catalog) else { return }
        let versionedDir = paths.serviceData(service, version: version)
        guard !fm.fileExists(atPath: versionedDir.path) else { return }

        do {
            if !fm.fileExists(atPath: flatDir.path) {
                try fm.createDirectory(at: flatDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            try fm.moveItem(at: migratingDir, to: versionedDir)
        } catch {}
    }

    private static func latestInstalled(_ kind: ServiceKind, catalog: ServiceBinaryCatalog) -> String? {
        catalog.installedVersions(kind).max { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    private static func hasDataMarker(at dir: URL, for kind: ServiceKind) -> Bool {
        let fm = FileManager.default
        switch kind {
        case .mysql:
            var isDir: ObjCBool = false
            let mysqlSubdir = dir.appendingPathComponent("mysql")
            return fm.fileExists(atPath: mysqlSubdir.path, isDirectory: &isDir) && isDir.boolValue
        case .postgres:
            return fm.fileExists(atPath: dir.appendingPathComponent("PG_VERSION").path)
        case .redis:
            if fm.fileExists(atPath: dir.appendingPathComponent("dump.rdb").path) { return true }
            let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            return contents.contains { $0.hasPrefix("appendonly") }
        case .mongodb:
            return fm.fileExists(atPath: dir.appendingPathComponent("WiredTiger").path)
                || fm.fileExists(atPath: dir.appendingPathComponent("storage.bson").path)
        default:
            return false
        }
    }
}
