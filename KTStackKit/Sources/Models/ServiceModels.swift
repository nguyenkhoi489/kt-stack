import SwiftUI

public enum ServiceStatus: String, CaseIterable, Sendable {
    case running, stopped, starting, stopping, warning, error, info

    public var color: Color {
        switch self {
        case .running:  return .KDStatus.running
        case .stopped:  return .KDStatus.stopped
        case .starting: return .KDStatus.starting
        case .stopping: return .KDStatus.starting
        case .warning:  return .KDStatus.warning
        case .error:    return .KDStatus.error
        case .info:     return .KDStatus.info
        }
    }

    public var symbolName: String {
        switch self {
        case .running:  return "circle.fill"
        case .stopped:  return "circle"
        case .starting: return "circle.dotted"
        case .stopping: return "circle.dotted"
        case .warning:  return "exclamationmark.triangle.fill"
        case .error:    return "xmark.octagon.fill"
        case .info:     return "info.circle"
        }
    }

    public var label: String {
        switch self {
        case .running:  return "Running"
        case .stopped:  return "Stopped"
        case .starting: return "Starting"
        case .stopping: return "Stopping"
        case .warning:  return "Warning"
        case .error:    return "Error"
        case .info:     return "Info"
        }
    }
}

public enum SiteType: String, Codable, CaseIterable, Sendable {
    case php
    case staticSite
    case node

    public var label: String {
        switch self {
        case .php:        return "PHP"
        case .staticSite: return "Static"
        case .node:       return "Node"
        }
    }
    public var symbolName: String {
        switch self {
        case .php:        return "chevron.left.forwardslash.chevron.right"
        case .staticSite: return "doc.richtext"
        case .node:       return "shippingbox"
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

    public init(id: UUID = UUID(),
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
                nodeEnabled: Bool = false) {
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
