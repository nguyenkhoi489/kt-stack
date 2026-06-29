import Foundation

public struct ServiceVersionStore: Sendable {
    private let paths: AppSupportPaths
    private let catalog: ServiceBinaryCatalog
    private var stored: [String: String]

    public init(paths: AppSupportPaths, catalog: ServiceBinaryCatalog) {
        self.paths = paths
        self.catalog = catalog
        let url = paths.config.appendingPathComponent("services.json")
        if let data = try? Data(contentsOf: url),
           let map = try? JSONDecoder().decode([String: String].self, from: data)
        {
            self.stored = map
        } else {
            self.stored = [:]
        }
    }

    public func activeVersion(_ kind: ServiceKind) -> String? {
        let installed = catalog.installedVersions(kind)
        guard !installed.isEmpty else { return nil }
        if let v = stored[kind.rawValue], installed.contains(v) {
            return v
        }
        return installed.max { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    public mutating func setActiveVersion(_ kind: ServiceKind, _ version: String) {
        stored[kind.rawValue] = version
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: paths.config, withIntermediateDirectories: true)
        try? data.write(to: paths.config.appendingPathComponent("services.json"), options: .atomic)
    }
}

public struct ServiceVersionError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}
