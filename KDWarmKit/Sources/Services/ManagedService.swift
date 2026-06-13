import Foundation

/// The seven services the Service Manager supervises. Each value is the single source of truth
/// for a service's identity: its UI label/symbol, its primary port, and its launchd label.
/// PHP-FPM is one logical service here even though it runs one launchd job per active PHP version
/// internally — the Services view shows a single aggregated PHP-FPM row.
public enum ServiceKind: String, CaseIterable, Sendable, Hashable {
    case nginx, phpFpm, dnsmasq, mysql, postgres, redis, mongodb, mailpit

    public var displayName: String {
        switch self {
        case .nginx:    return "Nginx"
        case .phpFpm:   return "PHP-FPM"
        case .dnsmasq:  return "dnsmasq"
        case .mysql:    return "MySQL"
        case .postgres: return "PostgreSQL"
        case .redis:    return "Redis"
        case .mongodb:  return "MongoDB"
        case .mailpit:  return "Mailpit"
        }
    }

    public var symbolName: String {
        switch self {
        case .nginx:    return "arrow.triangle.branch"
        case .phpFpm:   return "chevron.left.forwardslash.chevron.right"
        case .dnsmasq:  return "point.3.connected.trianglepath.dotted"
        case .mysql:    return "cylinder.split.1x2"
        case .postgres: return "cylinder.split.1x2.fill"
        case .redis:    return "bolt.fill"
        case .mongodb:  return "leaf.fill"
        case .mailpit:  return "envelope"
        }
    }

    /// Primary TCP port shown in the status pill (nil = no single port, e.g. PHP-FPM sockets).
    public var defaultPort: Int? {
        switch self {
        case .nginx:    return 443
        case .phpFpm:   return nil
        case .dnsmasq:  return 53
        case .mysql:    return 3306
        case .postgres: return 5432
        case .redis:    return 6379
        case .mongodb:  return 27017
        case .mailpit:  return 8025
        }
    }

    /// The binary name staged under `bin/` (nil for services without a single bundled binary).
    public var binaryName: String? {
        switch self {
        case .nginx:    return "nginx"
        case .phpFpm:   return "php-fpm"
        case .dnsmasq:  return "dnsmasq"
        case .mysql:    return "mysqld"
        case .postgres: return "postgres"
        case .redis:    return "redis-server"
        case .mongodb:  return "mongod"
        case .mailpit:  return "mailpit"
        }
    }

    /// launchd label for the service's primary job. PHP-FPM pools append `.<version>`.
    public var launchdLabel: String { "com.kdwarm.\(rawValue)" }
}

/// A long-running service the app supervises through launchd (it controls the job; it is not the
/// process parent, so services persist across app quit). Concrete controllers conform per service.
public protocol ManagedService: AnyObject, Sendable {
    var kind: ServiceKind { get }
    /// Pill text when running (port, version…). The aggregator falls back to a status label.
    var detail: String { get }
    /// `logsURL` for the Logs viewer (Phase 8). Nil until the service has produced a log.
    var logsURL: URL? { get }
    /// Whether the backing binary is staged. Un-bundled services (DBs awaiting a build pipeline)
    /// report `false` and surface a "Not installed" row instead of a failed start.
    var isInstalled: Bool { get }

    func start() async throws
    func stop() async throws
    func restart() async throws
    /// Live health probe → status. Cheap enough to poll sub-second (design §1.2).
    func probe() async -> ServiceStatus
}

/// Immutable, `Sendable` view of one service for the UI. `ServiceManager` publishes an array of
/// these; SwiftUI rows bind to them. Color never carries meaning alone — `status.symbolName`
/// pairs with it (design §3.2 / WCAG 1.4.1).
public struct ServiceSnapshot: Identifiable, Sendable, Hashable {
    public let kind: ServiceKind
    public var status: ServiceStatus
    public var detail: String
    public var isInstalled: Bool
    public var isBusy: Bool
    public var errorMessage: String?
    /// A not-installed engine that CAN be downloaded on demand (a catalog release exists).
    public var installable: Bool
    /// Download progress (0…1) while an on-demand install is in flight; nil otherwise.
    public var downloadFraction: Double?

    public var id: ServiceKind { kind }
    public var displayName: String { kind.displayName }
    public var symbolName: String { kind.symbolName }

    public init(kind: ServiceKind,
                status: ServiceStatus,
                detail: String,
                isInstalled: Bool,
                isBusy: Bool = false,
                errorMessage: String? = nil,
                installable: Bool = false,
                downloadFraction: Double? = nil) {
        self.kind = kind
        self.status = status
        self.detail = detail
        self.isInstalled = isInstalled
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.installable = installable
        self.downloadFraction = downloadFraction
    }
}
