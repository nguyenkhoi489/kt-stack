import Foundation

/// Verbose service-startup diagnostics written to logs/diagnostics.log.
/// Routine chatter (launchctl I/O, spec dumps) is recorded only when dev mode is on; warnings and
/// failures are always recorded so a "services won't start" report has data even with dev mode off.
public struct ServiceDiagnostics: Sendable {
    public enum Level: String, Sendable { case info, warn, error }

    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) {
        self.paths = paths
    }

    public static var isEnabled: Bool {
        if let v = ProcessInfo.processInfo.environment["KTSTACK_DEV"], v == "1" || v.lowercased() == "true" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "KTStack.devMode")
    }

    public var logURL: URL {
        paths.serviceLog("diagnostics")
    }

    public func log(_ level: Level, _ message: String) {
        if level == .info, !Self.isEnabled { return }
        Self.append("\(Self.stamp()) [\(level.rawValue.uppercased())] \(message)", to: logURL)
    }

    /// launchctl print for the job, trimmed to the fields that explain a failed start
    /// (state, pid, runs, last exit code/reason). This is where launchd records exec/spawn
    /// failures the service's own log never sees.
    public func launchdSummary(_ label: String) -> String {
        let res = LaunchAgentManager.launchctl(["print", "\(LaunchAgentManager.guiDomain)/\(label)"])
        guard res.code == 0 else { return "job not loaded (launchctl print rc=\(res.code))" }
        let wanted = ["state", "pid", "runs", "last exit code", "last exit reason"]
        var fields: [String] = []
        for raw in res.out.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            for key in wanted where line.hasPrefix("\(key) =") {
                fields.append(line)
            }
        }
        return fields.isEmpty ? "job loaded, no exit info reported" : fields.joined(separator: "; ")
    }

    public func logTail(_ url: URL, lines: Int = 8) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "(no log file at \(url.lastPathComponent))"
        }
        let all = text.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = all.suffix(lines).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? "(log empty)" : tail
    }

    private static let lock = NSLock()

    private static func append(_ line: String, to url: URL) {
        lock.lock(); defer { lock.unlock() }
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: url)
        }
    }

    private static let stampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func stamp() -> String {
        stampFormatter.string(from: Date())
    }
}
