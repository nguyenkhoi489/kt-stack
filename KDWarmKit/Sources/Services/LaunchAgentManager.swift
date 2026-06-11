import Foundation

/// Declarative description of a user LaunchAgent. Rendered to a plist and loaded via `launchctl
/// bootstrap` so the job persists across app quit; the app reattaches to it on next launch.
public struct LaunchAgentSpec: Sendable, Equatable {
    public let label: String
    public let programArguments: [String]
    public let workingDirectory: String?
    public let environment: [String: String]
    public let stdoutPath: String?
    public let stderrPath: String?
    /// Crash auto-restart: launchd relaunches the job whenever it exits non-zero (a crash or
    /// external `kill`). A clean stop is a `bootout`, which removes the job so this never fights it.
    public let keepAliveOnCrash: Bool
    public let runAtLoad: Bool

    public init(label: String,
                programArguments: [String],
                workingDirectory: String? = nil,
                environment: [String: String] = [:],
                stdoutPath: String? = nil,
                stderrPath: String? = nil,
                keepAliveOnCrash: Bool = true,
                runAtLoad: Bool = true) {
        self.label = label
        self.programArguments = programArguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.stdoutPath = stdoutPath
        self.stderrPath = stderrPath
        self.keepAliveOnCrash = keepAliveOnCrash
        self.runAtLoad = runAtLoad
    }
}

/// Writes/loads/kickstarts/boots-out user LaunchAgents and reconciles desired vs running on launch.
///
/// Jobs are bootstrapped into the per-user GUI domain (`gui/<uid>`). The app is a CONTROLLER: it
/// loads jobs but does not parent them, so quitting the app leaves running services up. Plists live
/// in app-support (not `~/Library/LaunchAgents`) so they are app-controlled, not auto-loaded at login.
public struct LaunchAgentManager: Sendable {
    public enum LaunchError: LocalizedError {
        case commandFailed(String, Int32, String)
        public var errorDescription: String? {
            switch self {
            case .commandFailed(let op, let code, let out):
                return "launchctl \(op) failed (\(code)): \(out)"
            }
        }
    }

    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) { self.paths = paths }

    /// Process-wide, short-TTL cache of the loaded job set in the user GUI domain. The health poll
    /// would otherwise spawn one `launchctl print <label>` per service every tick; instead all
    /// `isLoaded` reads share a single `launchctl print gui/<uid>` snapshot, refreshed at most once
    /// per `ttl`. Mutations (bootstrap/bootout) invalidate it so a state change reflects immediately.
    private static let loadedCache = LoadedLabelsCache()

    /// The per-user GUI launchd domain target (`gui/501`).
    public static var guiDomain: String { "gui/\(getuid())" }

    // MARK: - Plist rendering (pure — unit-tested without touching launchd)

    /// Render the LaunchAgent as a serialized XML plist `Data`.
    public func plistData(for spec: LaunchAgentSpec) throws -> Data {
        var dict: [String: Any] = [
            "Label": spec.label,
            "ProgramArguments": spec.programArguments,
            "RunAtLoad": spec.runAtLoad,
            "ProcessType": "Interactive",
        ]
        if let wd = spec.workingDirectory { dict["WorkingDirectory"] = wd }
        if !spec.environment.isEmpty { dict["EnvironmentVariables"] = spec.environment }
        if let out = spec.stdoutPath { dict["StandardOutPath"] = out }
        if let err = spec.stderrPath { dict["StandardErrorPath"] = err }
        // Restart only on a non-clean exit — a `bootout` (graceful stop) is exit 0 and stays down.
        if spec.keepAliveOnCrash { dict["KeepAlive"] = ["SuccessfulExit": false] }
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    /// Write the plist to `launchd/<label>.plist` and return its URL.
    @discardableResult
    public func writePlist(for spec: LaunchAgentSpec) throws -> URL {
        try paths.ensureDirectoryTree()
        let url = paths.launchAgentPlist(spec.label)
        try plistData(for: spec).write(to: url, options: .atomic)
        return url
    }

    // MARK: - launchctl lifecycle

    /// Load + start the job. Idempotent: if it is already loaded this is a no-op (reattach).
    public func bootstrap(_ spec: LaunchAgentSpec) throws {
        let plist = try writePlist(for: spec)
        if isLoaded(spec.label) { return }
        try run("bootstrap", [Self.guiDomain, plist.path])
        Self.loadedCache.invalidate()
    }

    /// Restart a loaded job in place (used for an explicit "Restart").
    public func kickstart(_ label: String) throws {
        try run("kickstart", ["-k", "\(Self.guiDomain)/\(label)"])
    }

    /// Stop + unload the job. Idempotent: a not-loaded job is treated as already stopped.
    public func bootout(_ label: String) throws {
        guard isLoaded(label) else { return }
        try run("bootout", ["\(Self.guiDomain)/\(label)"])
        Self.loadedCache.invalidate()
    }

    /// Whether launchd currently has the job loaded in the user domain. Backed by the shared,
    /// short-TTL snapshot so a poll loop checking many labels costs a single `launchctl print`.
    public func isLoaded(_ label: String) -> Bool {
        Self.loadedCache.contains(label)
    }

    /// Boot out every loaded `com.kdwarm.*` job in the user GUI domain (used by Uninstall/Reset).
    /// Best-effort. The root-owned helper daemon is unregistered separately via SMAppService;
    /// all KDWarm services run in `gui/<uid>`, so nothing is left in a system domain.
    public func bootoutAll() {
        for label in Self.loadedLabels() {
            try? run("bootout", ["\(Self.guiDomain)/\(label)"])
        }
        Self.loadedCache.invalidate()
    }

    private func run(_ op: String, _ args: [String]) throws {
        let res = Self.launchctl([op] + args)
        // bootstrap/bootout return code 5 (EIP) when already in the target state — benign.
        guard res.code == 0 || res.code == 5 else {
            throw LaunchError.commandFailed(op, res.code, res.out)
        }
    }

    /// Snapshot of currently-loaded KDWarm jobs in the user GUI domain (one `launchctl print`).
    static func loadedLabels() -> Set<String> {
        parseLoadedLabels(from: launchctl(["print", guiDomain]).out)
    }

    /// Extract `com.kdwarm.*` labels from the `services = { … }` block of `launchctl print` output.
    /// Pure (no I/O) so it is unit-tested against captured fixtures. Each service line ends in its
    /// label, e.g. `\t\t   637   -   com.kdwarm.redis`.
    static func parseLoadedLabels(from output: String) -> Set<String> {
        var labels = Set<String>()
        var inServices = false
        var depth = 0
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !inServices {
                if line.hasPrefix("services = {") { inServices = true; depth = 1 }
                continue
            }
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth <= 0 { break }
            if let token = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last,
               token.hasPrefix("com.kdwarm.") {
                labels.insert(String(token))
            }
        }
        return labels
    }

    /// Run `/bin/launchctl` and capture combined output + exit code.
    static func launchctl(_ args: [String]) -> (code: Int32, out: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// Process-wide cache of the loaded KDWarm job set with a short TTL. Shared by every
/// `LaunchAgentManager` instance so a health-poll tick checking N labels triggers at most one
/// `launchctl print` per TTL window. Thread-safe; explicitly invalidated on bootstrap/bootout.
final class LoadedLabelsCache: @unchecked Sendable {
    private let lock = NSLock()
    private let ttl: TimeInterval
    private var labels = Set<String>()
    private var fetchedAt = Date.distantPast

    init(ttl: TimeInterval = 0.5) { self.ttl = ttl }

    func contains(_ label: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if Date().timeIntervalSince(fetchedAt) > ttl {
            labels = LaunchAgentManager.loadedLabels()
            fetchedAt = Date()
        }
        return labels.contains(label)
    }

    func invalidate() {
        lock.lock(); fetchedAt = .distantPast; lock.unlock()
    }
}
