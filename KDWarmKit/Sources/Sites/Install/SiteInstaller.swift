import Foundation

public enum NewSiteKind: String, Sendable, CaseIterable, Identifiable {
    case wordpress, laravel
    public var id: String { rawValue }
    public var label: String { self == .wordpress ? "WordPress" : "Laravel" }
}

public struct NewSiteRequest: Sendable {
    public let name: String
    public let kind: NewSiteKind
    public let phpVersion: String
    public let folder: URL
    public let domain: String
    public let databaseName: String?
    public let siteTitle: String
    public let adminUser: String
    public let adminEmail: String
    public let adminPassword: String

    public init(name: String, kind: NewSiteKind, phpVersion: String, folder: URL, domain: String,
                databaseName: String?, siteTitle: String = "",
                adminUser: String = "admin", adminEmail: String = "admin@example.com",
                adminPassword: String = "") {
        self.name = name
        self.kind = kind
        self.phpVersion = phpVersion
        self.folder = folder
        self.domain = domain
        self.databaseName = databaseName
        self.siteTitle = siteTitle.isEmpty ? name : siteTitle
        self.adminUser = adminUser
        self.adminEmail = adminEmail
        self.adminPassword = adminPassword
    }
}

public enum InstallPhase: String, Sendable, Equatable {
    case preparing, configuringDatabase, scaffolding, finalizing, done
}

public struct InstallEvent: Sendable, Equatable {
    public let phase: InstallPhase
    public let message: String
    public init(phase: InstallPhase, message: String) {
        self.phase = phase
        self.message = message
    }
}

public enum InstallError: LocalizedError, Equatable {
    case folderExists(String)
    public var errorDescription: String? {
        switch self {
        case .folderExists(let name): return "A folder named “\(name)” already exists in your sites root."
        }
    }
}

public protocol SiteInstaller: Sendable {
    func scaffold(into folder: URL, request: NewSiteRequest,
                  emit: @Sendable (String) -> Void) async throws
}

public final class SiteInstallService: Sendable {
    private let database: DatabaseProvisioner
    public init(database: DatabaseProvisioner) { self.database = database }

    public func install(_ request: NewSiteRequest, installer: SiteInstaller,
                        register: @Sendable (URL) async throws -> Site,
                        emit: @Sendable @escaping (InstallEvent) -> Void) async throws -> Site {
        let fm = FileManager.default
        var createdDatabase: String?
        var createdFolder = false

        func rollback() async {
            if let db = createdDatabase { try? await database.dropDatabase(db) }
            if createdFolder { try? fm.removeItem(at: request.folder) }
        }

        do {
            emit(InstallEvent(phase: .preparing, message: "Preparing \(request.name)…"))
            guard !fm.fileExists(atPath: request.folder.path) else {
                throw InstallError.folderExists(request.folder.lastPathComponent)
            }
            try fm.createDirectory(at: request.folder, withIntermediateDirectories: true)
            createdFolder = true

            if let db = request.databaseName {
                try Task.checkCancellation()
                emit(InstallEvent(phase: .configuringDatabase, message: "Creating database \(db)…"))
                try await database.createDatabase(db)
                createdDatabase = db
            }

            try Task.checkCancellation()
            emit(InstallEvent(phase: .scaffolding, message: "Installing \(request.kind.label)…"))
            try await installer.scaffold(into: request.folder, request: request) { line in
                emit(InstallEvent(phase: .scaffolding, message: line))
            }

            try Task.checkCancellation()
            emit(InstallEvent(phase: .finalizing, message: "Registering site…"))
            let site = try await register(request.folder)
            emit(InstallEvent(phase: .done, message: "Site ready at https://\(request.domain)"))
            return site
        } catch {
            await rollback()
            throw error
        }
    }
}
