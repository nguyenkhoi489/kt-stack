import Foundation
import Network

public enum ServerStatus: Equatable, Sendable {
    case connecting
    case online
    case offline
}

@MainActor
public final class ServerReachabilityService: ObservableObject {
    @Published public private(set) var statuses: [UUID: ServerStatus] = [:]

    private let probeInterval: TimeInterval
    private let probeTimeout: TimeInterval
    private var profilesProvider: () -> [ConnectionProfile] = { [] }
    private var managedRunningProvider: (DatabaseKind) -> Bool = { _ in false }
    private var pollTask: Task<Void, Never>?

    public init(probeInterval: TimeInterval = 5, probeTimeout: TimeInterval = 1.2) {
        self.probeInterval = probeInterval
        self.probeTimeout = probeTimeout
    }

    public func configure(
        profiles: @escaping () -> [ConnectionProfile],
        managedRunning: @escaping (DatabaseKind) -> Bool
    ) {
        profilesProvider = profiles
        managedRunningProvider = managedRunning
    }

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.probeAll()
                let interval = self?.probeInterval ?? 5
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func currentStatus(for profileID: UUID) -> ServerStatus {
        statuses[profileID] ?? .connecting
    }

    private func probeAll() async {
        let profiles = profilesProvider()
        let liveIDs = Set(profiles.map(\.id))
        statuses = statuses.filter { liveIDs.contains($0.key) }
        for profile in profiles where statuses[profile.id] == nil {
            statuses[profile.id] = .connecting
        }
        var managedFlags: [UUID: Bool] = [:]
        for profile in profiles where profile.isManaged {
            managedFlags[profile.id] = managedRunningProvider(profile.kind)
        }
        let timeout = probeTimeout
        await withTaskGroup(of: (UUID, ServerStatus).self) { group in
            for profile in profiles {
                let managedRunning = managedFlags[profile.id] ?? false
                group.addTask {
                    let status = await Self.probe(profile: profile, managedRunning: managedRunning, timeout: timeout)
                    return (profile.id, status)
                }
            }
            for await (id, status) in group {
                statuses[id] = status
            }
        }
    }

    public enum ProbeOutcome: Equatable, Sendable {
        case managed(running: Bool)
        case file(exists: Bool)
        case tcp(reachable: Bool)
    }

    public nonisolated static func map(_ outcome: ProbeOutcome) -> ServerStatus {
        switch outcome {
        case let .managed(running): running ? .online : .offline
        case let .file(exists): exists ? .online : .offline
        case let .tcp(reachable): reachable ? .online : .offline
        }
    }

    public nonisolated static func outcome(
        for profile: ConnectionProfile,
        managedRunning: Bool,
        tcpReachable: Bool,
        fileExists: Bool
    ) -> ProbeOutcome {
        if profile.isManaged { return .managed(running: managedRunning) }
        switch profile.kind {
        case .sqlite: return .file(exists: fileExists)
        default: return .tcp(reachable: tcpReachable)
        }
    }

    nonisolated static func probe(profile: ConnectionProfile, managedRunning: Bool, timeout: TimeInterval) async -> ServerStatus {
        if profile.isManaged {
            return map(.managed(running: managedRunning))
        }
        switch profile.kind {
        case .sqlite:
            let exists = profile.filePath.map { FileManager.default.fileExists(atPath: $0) } ?? false
            return map(.file(exists: exists))
        default:
            let reachable = await probeTCP(host: profile.host, port: profile.port, timeout: timeout)
            return map(.tcp(reachable: reachable))
        }
    }

    nonisolated static func probeTCP(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        guard port > 0, port <= 65535, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let resumeGuard = ProbeResumeGuard()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumeGuard.claim() { connection.cancel(); continuation.resume(returning: true) }
                case .failed, .cancelled:
                    if resumeGuard.claim() { connection.cancel(); continuation.resume(returning: false) }
                default:
                    break
                }
            }
            connection.start(queue: Self.probeQueue)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if resumeGuard.claim() { connection.cancel(); continuation.resume(returning: false) }
            }
        }
    }

    private nonisolated static let probeQueue = DispatchQueue(label: "com.ktstack.server-reachability")
}

private final class ProbeResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
