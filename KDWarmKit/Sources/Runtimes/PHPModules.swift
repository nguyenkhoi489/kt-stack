import Foundation

/// Reads the compiled-in extension list of an installed PHP version via `php -m` and caches it per
/// version. The set is fixed at build time (static PHP can't dlopen), so the result never changes for
/// a given installed binary — caching once is safe and keeps it off the UI render path after the
/// first read. Surfaced read-only in the Runtimes PHP card.
public enum PHPModules {
    /// Thread-safe per-version cache. `@unchecked Sendable` because access is serialized by the lock.
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var byVersion: [String: [String]] = [:]
    }
    private static let cache = Cache()

    /// Loaded extensions for an installed PHP version (`php -m`), lowercased + sorted, "Zend"-section
    /// headers and blanks stripped. Returns [] if the binary is missing or the probe fails (treated as
    /// "unknown" by callers). Runs the binary at most once per version — subsequent calls hit the cache.
    public static func list(version: String, paths: AppSupportPaths = AppSupportPaths()) -> [String] {
        cache.lock.lock()
        if let hit = cache.byVersion[version] { cache.lock.unlock(); return hit }
        cache.lock.unlock()

        let mods = probe(version: version, paths: paths)
        cache.lock.lock(); cache.byVersion[version] = mods; cache.lock.unlock()
        return mods
    }

    /// Drop a cached entry (e.g. after a version is reinstalled). Next `list` re-probes.
    public static func invalidate(version: String) {
        cache.lock.lock(); cache.byVersion[version] = nil; cache.lock.unlock()
    }

    /// Modules an installed PHP loads with an explicit `PHP_INI_SCAN_DIR` — so optional extensions in
    /// `runtimes/php/<v>/conf.d` are included. The cached `list` runs a BARE `php -m` (compiled scan
    /// dir, which our relocatable build does not have), so it only ever sees compiled-in modules;
    /// install-state for optional `.so`s MUST use this. Uncached: the set changes on install/uninstall.
    public static func loadedModules(version: String, scanDir: URL,
                                     paths: AppSupportPaths = AppSupportPaths()) -> [String] {
        let php = paths.phpBinary(version: version)
        guard FileManager.default.isExecutableFile(atPath: php.path) else { return [] }
        let proc = Process()
        proc.executableURL = php
        proc.arguments = ["-m"]
        var env = ProcessInfo.processInfo.environment
        env["PHP_INI_SCAN_DIR"] = scanDir.path
        proc.environment = env
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text)
    }

    private static func probe(version: String, paths: AppSupportPaths) -> [String] {
        let php = paths.phpBinary(version: version)
        guard FileManager.default.isExecutableFile(atPath: php.path) else { return [] }

        let proc = Process()
        proc.executableURL = php
        proc.arguments = ["-m"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// Parse `php -m` output: skip `[PHP Modules]` / `[Zend Modules]` headers and blank lines, then
    /// lowercase, de-dupe, and sort. Exposed `internal` for unit tests.
    static func parse(_ output: String) -> [String] {
        var seen = Set<String>()
        var mods: [String] = []
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("[") else { continue }
            let name = line.lowercased()
            if seen.insert(name).inserted { mods.append(name) }
        }
        return mods.sorted()
    }
}
