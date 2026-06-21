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

    public init(id: UUID = UUID(),
                name: String,
                path: String,
                docroot: String,
                domain: String,
                phpVersion: String,
                type: SiteType,
                databaseName: String? = nil,
                secure: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.docroot = docroot
        self.domain = domain
        self.phpVersion = phpVersion
        self.type = type
        self.databaseName = databaseName
        self.secure = secure
    }

    public static let sample: [Site] = []
}
