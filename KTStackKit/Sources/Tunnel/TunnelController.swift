import Foundation

public actor TunnelController {
    enum ProbeDecision: Equatable {
        case pending
        case ready
        case failed(String)
    }

    private let paths: AppSupportPaths
    private let label: String
    private let logURL: URL
    private let launch: LaunchAgentManager

    private var monitor: Task<Void, Never>?
    private var userStopped = false
    private var cancelled = false
    private var logOffset: UInt64 = 0

    private struct ProbeResult {
        let statusCode: Int
        let location: URL?
    }

    private static let parseTimeout: TimeInterval = 30
    private static let probeTimeout: TimeInterval = 60
    // Cloudflare's edge returns these while the tunnel is still warming up, so treat them as "keep
    // polling" rather than a failure; a real origin error surfaces a different code.
    private static let edgeErrorCodes: Set<Int> = [502, 503, 504, 521, 522, 523, 524, 530]

    public init(paths: AppSupportPaths, siteID: UUID) {
        self.paths = paths
        label = paths.tunnelLabel(siteID.uuidString)
        logURL = paths.tunnelLog(siteID.uuidString)
        launch = LaunchAgentManager(paths: paths)
    }

    public func start(
        binary: URL,
        originPort: Int,
        localDomain: String,
        onURL: @escaping @Sendable (URL) async -> Void = { _ in },
        onStatus: @escaping @Sendable (TunnelStatus) -> Void
    ) async {
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
            programArguments: [binary.path] + TunnelOrigin.cloudflaredArguments(port: originPort),
            stdoutPath: logURL.path,
            stderrPath: logURL.path,
            keepAliveOnCrash: false,
            runAtLoad: true
        )
        do {
            try launch.bootstrap(spec)
        } catch {
            onStatus(.error(error.localizedDescription))
            return
        }
        monitor = Task { await self.awaitURL(localDomain: localDomain, onURL: onURL, onStatus: onStatus) }
    }

    public func stop() {
        cancelled = true
        userStopped = true
        monitor?.cancel()
        monitor = nil
        try? launch.bootout(label)
    }

    private func awaitURL(
        localDomain: String,
        onURL: @escaping @Sendable (URL) async -> Void,
        onStatus: @escaping @Sendable (TunnelStatus) -> Void
    ) async {
        let deadline = Date().addingTimeInterval(Self.parseTimeout)
        var buffer = ""
        var poll = 0
        while Date() < deadline {
            if Task.isCancelled || userStopped { return }
            buffer += readNewLogBytes()
            if let url = TrycloudflareURL.first(in: buffer) {
                await onURL(url)
                if Task.isCancelled || userStopped { return }
                await probeThenPublish(url: url, localDomain: localDomain, onStatus: onStatus)
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
        if !userStopped {
            onStatus(.error(
                connectivityDiagnosis()
                    ?? "URL not received within \(Int(Self.parseTimeout))s."
            ))
        }
    }

    private func probeThenPublish(
        url: URL,
        localDomain: String,
        onStatus: @escaping @Sendable (TunnelStatus) -> Void
    ) async {
        let deadline = Date().addingTimeInterval(Self.probeTimeout)
        var poll = 0
        while Date() < deadline {
            if Task.isCancelled || userStopped { return }
            switch await Self.probeDecision(for: Self.httpProbe(of: url), publicURL: url, localDomain: localDomain) {
            case .ready:
                if !userStopped { onStatus(.active(url)) }
                return
            case let .failed(message):
                try? launch.bootout(label)
                if !userStopped { onStatus(.error(message)) }
                return
            case .pending:
                break
            }
            poll += 1
            if poll % 5 == 0, !launch.isLoadedNow(label) {
                if !userStopped { onStatus(.error("cloudflared exited before the tunnel became reachable.")) }
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        if userStopped { return }
        if launch.isLoadedNow(label) {
            onStatus(.activeUnverified(url))
            return
        }
        if !userStopped {
            onStatus(.error(
                connectivityDiagnosis()
                    ?? "Tunnel URL did not become reachable within \(Int(Self.probeTimeout))s. Check DNS/network and share again."
            ))
        }
    }

    private func connectivityDiagnosis() -> String? {
        guard let data = try? Data(contentsOf: logURL),
              let log = String(data: data, encoding: .utf8) else { return nil }
        return Self.connectivityDiagnosis(log: log)
    }

    static func connectivityDiagnosis(log: String) -> String? {
        let blocked = [
            "QUIC connection failed",
            "HTTP/2 connection is blocked or unreachable",
            "Environment has critical failures",
            "Allow outbound QUIC traffic on port 7844",
        ]
        if blocked.contains(where: log.contains) {
            return "Couldn't establish a Cloudflare tunnel — this network restricts cloudflared (UDP/QUIC, or outbound port 7844). It may still work on another network; try again or switch networks."
        }
        if log.contains("i/o timeout") || log.contains("no such host") {
            return "Couldn't establish a Cloudflare tunnel — DNS/network connectivity to the edge failed. Check your internet connection and share again."
        }
        return nil
    }

    // launchd refuses to bootstrap a label that is still loaded, so boot out the old job and wait
    // for it to actually disappear before starting a new one.
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

    static func probeDecision(
        statusCode: Int?,
        locationHost: String?,
        publicHost: String?,
        localDomain: String
    ) -> ProbeDecision {
        guard let statusCode else { return .pending }
        if Self.edgeErrorCodes.contains(statusCode) { return .pending }
        if (300..<400).contains(statusCode),
           let locationHost,
           locationHost == localDomain || locationHost.hasSuffix(".test")
        {
            return .failed("Tunnel reached the site, but it redirects to local URL \(locationHost). Disable the local-domain redirect or update the app URL before sharing.")
        }
        if let locationHost, let publicHost,
           (300..<400).contains(statusCode), locationHost != publicHost
        {
            return .failed("Tunnel reached the site, but it redirects to \(locationHost).")
        }
        return .ready
    }

    private static func probeDecision(
        for result: ProbeResult?,
        publicURL: URL,
        localDomain: String
    ) -> ProbeDecision {
        probeDecision(
            statusCode: result?.statusCode,
            locationHost: result?.location?.host,
            publicHost: publicURL.host,
            localDomain: localDomain
        )
    }

    private static func httpProbe(of url: URL) async -> ProbeResult? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let config = URLSessionConfiguration.ephemeral
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return nil }
            let location = response.value(forHTTPHeaderField: "Location")
                .flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
            return ProbeResult(statusCode: response.statusCode, location: location)
        } catch {
            return nil
        }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
