import Foundation
#if canImport(ServiceManagement)
    import ServiceManagement
#endif

public enum LegacyKDWarmMigration {
    private static let didMigrateKey = "ktstack.didMigrateFromKDWarm.v1"
    private static let legacyDataDirName = "KDWarm"
    private static let legacyDefaultsSuite = "com.kdwarm.app"
    private static let legacyKeychainService = "com.kdwarm.db"
    private static let currentKeychainService = "com.ktstack.db"
    private static let legacyLaunchPrefix = "com.kdwarm."
    private static let legacyHelperPlist = "com.kdwarm.helper.plist"

    public static func runIfNeeded(
        paths: AppSupportPaths = AppSupportPaths(),
        defaults: UserDefaults = .standard
    ) {
        guard !defaults.bool(forKey: didMigrateKey) else { return }

        let fileManager = FileManager.default
        let newRoot = paths.root
        let legacyRoot = newRoot.deletingLastPathComponent()
            .appendingPathComponent(legacyDataDirName, isDirectory: true)
        let hasLegacyData = fileManager.fileExists(atPath: legacyRoot.path)

        if hasLegacyData {
            // Stop the legacy launchd jobs before moving their data dir, or the still-running
            // daemons keep writing into the old path mid-move and corrupt the relocation.
            LaunchAgentManager(paths: paths).bootout(matchingPrefix: legacyLaunchPrefix)
            _ = relocateDataDirectory(from: legacyRoot, to: newRoot)
        }

        purgeLegacyLaunchPlists(in: paths)
        KeychainStore.migrateService(from: legacyKeychainService, to: currentKeychainService)
        migrateDefaults(into: defaults)
        unregisterLegacyHelper()

        defaults.set(true, forKey: didMigrateKey)
    }

    @discardableResult
    static func relocateDataDirectory(
        from legacyRoot: URL,
        to newRoot: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: legacyRoot.path),
              !fileManager.fileExists(atPath: newRoot.path) else { return false }
        do {
            try fileManager.moveItem(at: legacyRoot, to: newRoot)
            return true
        } catch {
            return false
        }
    }

    static func purgeLegacyLaunchPlists(in paths: AppSupportPaths) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: paths.launchAgents, includingPropertiesForKeys: nil
        ) else { return }
        for url in entries where url.lastPathComponent.hasPrefix(legacyLaunchPrefix) {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func migrateDefaults(into defaults: UserDefaults) {
        let legacyDefaults = UserDefaults()
        guard let domain = legacyDefaults.persistentDomain(forName: legacyDefaultsSuite),
              !domain.isEmpty else { return }
        for (key, value) in domain where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        legacyDefaults.removePersistentDomain(forName: legacyDefaultsSuite)
    }

    private static func unregisterLegacyHelper() {
        #if canImport(ServiceManagement)
            if #available(macOS 13.0, *) {
                try? SMAppService.daemon(plistName: legacyHelperPlist).unregister()
            }
        #endif
    }
}
