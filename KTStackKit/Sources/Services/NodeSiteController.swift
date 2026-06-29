import Foundation

public struct NodeSiteController: Sendable {
    public enum State: String, Equatable, Sendable {
        case running, stopped
    }

    private let health = HealthChecker()

    public init() {}

    public func probe(_ site: Site) async -> State {
        guard let port = site.nodePort else { return .stopped }
        return await health.check(.tcp(port: port)) == .running ? .running : .stopped
    }
}

public extension NodeSiteController.State {
    var badgeLabel: String {
        switch self {
        case .running: "Running"
        case .stopped: "Stopped"
        }
    }

    var isHealthy: Bool {
        self == .running
    }

    var serviceStatus: ServiceStatus {
        switch self {
        case .running: .running
        case .stopped: .stopped
        }
    }
}
