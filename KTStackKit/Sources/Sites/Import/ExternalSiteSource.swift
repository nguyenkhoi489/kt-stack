import Foundation

public struct DiscoveredSite: Identifiable, Sendable, Hashable {
    public let tool: String
    public let name: String
    public let path: URL
    public let domain: String
    public let phpVersion: String?
    public let experimental: Bool

    public var id: String {
        "\(tool):\(path.path)"
    }

    public init(
        tool: String,
        name: String,
        path: URL,
        domain: String,
        phpVersion: String?,
        experimental: Bool = false
    ) {
        self.tool = tool
        self.name = name
        self.path = path
        self.domain = domain
        self.phpVersion = phpVersion
        self.experimental = experimental
    }
}

public protocol ExternalSiteSource: Sendable {
    var tool: String { get }
    var isAvailable: Bool { get }
    func discover() -> [DiscoveredSite]
}

public enum ImportSafety {
    public struct UnsafeTarget: LocalizedError, Equatable {
        public let reason: String
        public var errorDescription: String? {
            reason
        }
    }

    public static func resolvedSafeDocroot(
        _ path: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let real = URL(fileURLWithPath: (path.path as NSString).resolvingSymlinksInPath)
            .standardizedFileURL
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: real.path, isDirectory: &isDir), isDir.boolValue else {
            throw UnsafeTarget(reason: "“\(real.path)” does not exist or is not a folder.")
        }
        let attributes = try fileManager.attributesOfItem(atPath: real.path)
        guard let owner = attributes[.ownerAccountID] as? NSNumber, owner.uint32Value == getuid() else {
            throw UnsafeTarget(reason: "“\(real.path)” is not owned by the current user — refusing to serve it.")
        }
        return real
    }
}

public enum ExternalSiteDiscovery {
    public static func allSources() -> [ExternalSiteSource] {
        [LocalSiteSource(), ValetSiteSource(), HerdSiteSource(), MAMPSiteSource()]
    }

    public static func discoverAll() -> [DiscoveredSite] {
        allSources().filter(\.isAvailable).flatMap { $0.discover() }
    }
}
