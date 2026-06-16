import Foundation

public actor TunnelController {
    private let paths: AppSupportPaths
    private let label: String
    private let logURL: URL
    private let launch: LaunchAgentManager

    private var monitor: Task<Void, Never>?
    private var userStopped = false
    private var cancelled = false
    private var logOffset: UInt64 = 0

    private static let parseTimeout: TimeInterval = 30
    private static let probeTimeout: TimeInterval = 60
    private static let edgeErrorCodes: Set<Int> = [502, 503, 504, 521, 522, 523, 524, 530]

    public init(paths: AppSupportPaths, siteID: UUID) {
        self.paths = paths
        self.label = paths.tunnelLabel(siteID.uuidString)
        self.logURL = paths.tunnelLog(siteID.uuidString)
        self.launch = LaunchAgentManager(paths: paths)
    }

    public func start(binary: URL, domain: String, secure: Bool,
                      onStatus: @escaping @Sendable (TunnelStatus) -> Void) async {
        if cancelled { return }
        userStopped = false
        logOffset = 0
        onStatus(.starting)
        await ensureLabelFree()
        if cancelled || userStopped { return }
        let fm = FileManager.default
        try? fm.removeItem(at: logURL)
        fm.createFile(atPath: logURL.path, contents: nil)
        let spec = LaunchAgentSpec(
            label: label,
            programArguments: [binary.path] + TunnelOrigin.cloudflaredArguments(secure: secure, domain: domain),
            stdoutPath: logURL.path,
            stderrPath: logURL.path,
            keepAliveOnCrash: false,
            runAtLoad: true)
        do {
            try launch.bootstrap(spec)
        } catch {
            onStatus(.error(error.localizedDescription))
            return
        }
        monitor = Task { await self.awaitURL(onStatus: onStatus) }
    }

    public func stop() {
        cancelled = true
        userStopped = true
        monitor?.cancel()
        monitor = nil
        try? launch.bootout(label)
    }

    private func awaitURL(onStatus: @escaping @Sendable (TunnelStatus) -> Void) async {
        let deadline = Date().addingTimeInterval(Self.parseTimeout)
        var buffer = ""
        var poll = 0
        while Date() < deadline {
            if Task.isCancelled || userStopped { return }
            buffer += readNewLogBytes()
            if let url = TrycloudflareURL.first(in: buffer) {
                await probeThenPublish(url: url, onStatus: onStatus)
                return
            }
            poll += 1
            if poll % 3 == 0, !launch.isLoadedNow(label) {
                if !userStopped { onStatus(.error("cloudflared exited before publishing a URL.")) }
                return
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        try? launch.bootout(label)
        if !userStopped { onStatus(.error("URL not received within \(Int(Self.parseTimeout))s.")) }
    }

    private func probeThenPublish(url: URL, onStatus: @escaping @Sendable (TunnelStatus) -> Void) async {
        let deadline = Date().addingTimeInterval(Self.probeTimeout)
        var poll = 0
        while Date() < deadline {
            if Task.isCancelled || userStopped { return }
            if let code = await Self.httpStatus(of: url), !Self.edgeErrorCodes.contains(code) {
                if !userStopped { onStatus(.active(url)) }
                return
            }
            poll += 1
            if poll % 5 == 0, !launch.isLoadedNow(label) {
                if !userStopped { onStatus(.error("cloudflared exited before the tunnel became reachable.")) }
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        if !userStopped { onStatus(.active(url)) }
    }

    private func ensureLabelFree() async {
        guard launch.isLoadedNow(label) else { return }
        try? launch.bootout(label)
        for _ in 0..<15 {
            if !launch.isLoadedNow(label) { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func readNewLogBytes() -> String {
        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return "" }
        defer { try? handle.close() }
        try? handle.seek(toOffset: logOffset)
        let data = handle.readDataToEndOfFile()
        logOffset += UInt64(data.count)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func httpStatus(of url: URL) async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }
}
