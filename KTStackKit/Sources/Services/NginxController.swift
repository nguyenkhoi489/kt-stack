import Foundation

public final class NginxController: @unchecked Sendable {
    public enum ControlError: LocalizedError, Equatable {
        case commandFailed([String], Int32, String)

        public var errorDescription: String? {
            switch self {
            case let .commandFailed(args, code, output):
                let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
                let command = (["nginx"] + args).joined(separator: " ")
                if detail.isEmpty { return "\(command) failed with exit code \(code)." }
                return "\(command) failed with exit code \(code): \(detail)"
            }
        }
    }

    private let paths: AppSupportPaths
    private let agents: LaunchAgentManager
    private let label = ServiceKind.nginx.launchdLabel
    private static let fileDescriptorLimit = 8192
    private var cachedBuildInfo: String?

    public init(paths: AppSupportPaths, agents: LaunchAgentManager) {
        self.paths = paths
        self.agents = agents
    }

    public var isRunning: Bool {
        agents.isLoaded(label)
    }

    public func start() throws {
        try agents.bootstrap(spec())
    }

    public func reload() throws {
        try runControlCommand(["-s", "reload"])
    }

    public func restart() throws {
        stop()
        try start()
    }

    public func supportsResponseBodyRewrite() -> Bool {
        buildInfo().contains("http_sub_module")
    }

    private func buildInfo() -> String {
        if let cachedBuildInfo { return cachedBuildInfo }
        let proc = Process()
        proc.executableURL = paths.nginxBinary
        proc.arguments = ["-V"]
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = pipe
        guard (try? proc.run()) != nil else { cachedBuildInfo = ""; return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let info = String(data: data, encoding: .utf8) ?? ""
        cachedBuildInfo = info
        return info
    }

    public func stop(grace _: TimeInterval = 3.0) {
        try? agents.bootout(label)
    }

    private func spec() -> LaunchAgentSpec {
        LaunchAgentSpec(
            label: label,
            programArguments: [
                paths.nginxBinary.path,
                "-p", paths.root.path,
                "-c", paths.nginxConf.path,
                "-g", "daemon off;",
            ],
            workingDirectory: paths.root.path,
            stdoutPath: paths.nginxErrorLog.path,
            stderrPath: paths.nginxErrorLog.path,
            fileDescriptorLimit: Self.fileDescriptorLimit
        )
    }

    private func runControlCommand(_ extra: [String]) throws {
        let proc = Process()
        proc.executableURL = paths.nginxBinary
        proc.arguments = ["-p", paths.root.path, "-c", paths.nginxConf.path] + extra
        proc.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        proc.standardError = pipe
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let output = String(data: data, encoding: .utf8) ?? ""
            throw ControlError.commandFailed(extra, proc.terminationStatus, output)
        }
    }
}
