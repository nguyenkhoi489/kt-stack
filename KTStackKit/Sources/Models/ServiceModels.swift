import SwiftUI

public enum ServiceStatus: String, CaseIterable, Sendable {
    case running, stopped, starting, stopping, warning, error, info

    public var color: Color {
        switch self {
        case .running: .KDStatus.running
        case .stopped: .KDStatus.stopped
        case .starting: .KDStatus.starting
        case .stopping: .KDStatus.starting
        case .warning: .KDStatus.warning
        case .error: .KDStatus.error
        case .info: .KDStatus.info
        }
    }

    public var symbolName: String {
        switch self {
        case .running: "circle.fill"
        case .stopped: "circle"
        case .starting: "circle.dotted"
        case .stopping: "circle.dotted"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .info: "info.circle"
        }
    }

    public var label: String {
        switch self {
        case .running: "Running"
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .stopping: "Stopping"
        case .warning: "Warning"
        case .error: "Error"
        case .info: "Info"
        }
    }
}

public enum SiteType: String, Codable, CaseIterable, Sendable {
    case php
    case staticSite
    case node

    public var label: String {
        switch self {
        case .php: "PHP"
        case .staticSite: "Static"
        case .node: "Node"
        }
    }

    public var symbolName: String {
        switch self {
        case .php: "chevron.left.forwardslash.chevron.right"
        case .staticSite: "doc.richtext"
        case .node: "shippingbox"
        }
    }
}

public struct Site: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var path: String
    public var docroot: String
    public var domain: String
    public var phpVersion: String
    public var type: SiteType
    public var databaseName: String?
    public var secure: Bool
    public var nodePort: Int?
    public var nodeCommand: String?
    public var nodeEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        docroot: String,
        domain: String,
        phpVersion: String,
        type: SiteType,
        databaseName: String? = nil,
        secure: Bool = false,
        nodePort: Int? = nil,
        nodeCommand: String? = nil,
        nodeEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.docroot = docroot
        self.domain = domain
        self.phpVersion = phpVersion
        self.type = type
        self.databaseName = databaseName
        self.secure = secure
        self.nodePort = nodePort
        self.nodeCommand = nodeCommand
        self.nodeEnabled = nodeEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, path, docroot, domain, phpVersion, type, databaseName, secure
        case nodePort, nodeCommand, nodeEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        docroot = try c.decode(String.self, forKey: .docroot)
        domain = try c.decode(String.self, forKey: .domain)
        phpVersion = try c.decode(String.self, forKey: .phpVersion)
        type = try c.decode(SiteType.self, forKey: .type)
        databaseName = try c.decodeIfPresent(String.self, forKey: .databaseName)
        secure = try c.decodeIfPresent(Bool.self, forKey: .secure) ?? false
        nodePort = try c.decodeIfPresent(Int.self, forKey: .nodePort)
        nodeCommand = try c.decodeIfPresent(String.self, forKey: .nodeCommand)
        nodeEnabled = try c.decodeIfPresent(Bool.self, forKey: .nodeEnabled) ?? false
    }

    public static let sample: [Site] = []
}
