import Foundation

public enum ServiceKind: String, CaseIterable, Sendable, Hashable {
    case nginx, phpFpm, dnsmasq, mysql, postgres, redis, mongodb, mailpit

    public var displayName: String {
        switch self {
        case .nginx: "Nginx"
        case .phpFpm: "PHP-FPM"
        case .dnsmasq: "dnsmasq"
        case .mysql: "MySQL"
        case .postgres: "PostgreSQL"
        case .redis: "Redis"
        case .mongodb: "MongoDB"
        case .mailpit: "Mailpit"
        }
    }

    public var symbolName: String {
        switch self {
        case .nginx: "arrow.triangle.branch"
        case .phpFpm: "chevron.left.forwardslash.chevron.right"
        case .dnsmasq: "point.3.connected.trianglepath.dotted"
        case .mysql: "cylinder.split.1x2"
        case .postgres: "cylinder.split.1x2.fill"
        case .redis: "bolt.fill"
        case .mongodb: "leaf.fill"
        case .mailpit: "envelope"
        }
    }

    public var defaultPort: Int? {
        switch self {
        case .nginx: 443
        case .phpFpm: nil
        case .dnsmasq: 53
        case .mysql: 3306
        case .postgres: 5432
        case .redis: 6379
        case .mongodb: 27017
        case .mailpit: 8025
        }
    }

    public var binaryName: String? {
        switch self {
        case .nginx: "nginx"
        case .phpFpm: "php-fpm"
        case .dnsmasq: "dnsmasq"
        case .mysql: "mysqld"
        case .postgres: "postgres"
        case .redis: "redis-server"
        case .mongodb: "mongod"
        case .mailpit: "mailpit"
        }
    }

    public var launchdLabel: String {
        "com.ktstack.\(rawValue)"
    }
}

public protocol ManagedService: AnyObject, Sendable {
    var kind: ServiceKind { get }

    var detail: String { get }

    var logsURL: URL? { get }

    var isInstalled: Bool { get }

    func start() async throws
    func stop() async throws
    func restart() async throws

    func probe() async -> ServiceStatus
}

public struct ServiceSnapshot: Identifiable, Sendable, Hashable {
    public let kind: ServiceKind
    public var status: ServiceStatus
    public var detail: String
    public var isInstalled: Bool
    public var isBusy: Bool
    public var errorMessage: String?

    public var installable: Bool

    public var downloadFraction: Double?

    public var cpuPercent: Double?

    public var memoryBytes: Int64?

    public var id: ServiceKind {
        kind
    }

    public var displayName: String {
        kind.displayName
    }

    public var symbolName: String {
        kind.symbolName
    }

    public var metricsText: String? {
        guard status == .running else { return nil }
        var parts: [String] = []
        if let cpuPercent { parts.append(String(format: "CPU %.1f%%", cpuPercent)) }
        if let memoryBytes { parts.append("\(memoryBytes / 1_048_576) MB") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public init(
        kind: ServiceKind,
        status: ServiceStatus,
        detail: String,
        isInstalled: Bool,
        isBusy: Bool = false,
        errorMessage: String? = nil,
        installable: Bool = false,
        downloadFraction: Double? = nil,
        cpuPercent: Double? = nil,
        memoryBytes: Int64? = nil
    ) {
        self.kind = kind
        self.status = status
        self.detail = detail
        self.isInstalled = isInstalled
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.installable = installable
        self.downloadFraction = downloadFraction
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}
