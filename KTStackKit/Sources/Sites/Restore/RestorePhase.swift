import Foundation

public enum RestorePhase: String, Sendable, Equatable {
    case detecting
    case extracting
    case reconcilingCore
    case creatingDatabase
    case importingDatabase
    case repairingEncoding
    case writingConfig
    case searchReplace
    case installingFiles
    case configuringServer
    case done
}

public struct RestoreEvent: Sendable, Equatable {
    public let phase: RestorePhase
    public let message: String

    public init(phase: RestorePhase, message: String) {
        self.phase = phase
        self.message = message
    }
}

public struct RestoreRequest: Sendable {
    public let backupFile: URL
    public let siteFolder: URL
    public let siteDomain: String
    public let phpVersion: String
    public let secure: Bool
    public let repairEncoding: Bool

    public init(backupFile: URL, siteFolder: URL, siteDomain: String, phpVersion: String,
                secure: Bool, repairEncoding: Bool) {
        self.backupFile = backupFile
        self.siteFolder = siteFolder
        self.siteDomain = siteDomain
        self.phpVersion = phpVersion
        self.secure = secure
        self.repairEncoding = repairEncoding
    }
}

public struct RestoreOutcome: Sendable {
    public let domain: String
    public let warnings: [String]

    public init(domain: String, warnings: [String]) {
        self.domain = domain
        self.warnings = warnings
    }
}

public enum RestoreServiceError: LocalizedError, Equatable {
    case phpVersionNotInstalled(String)
    case sourceURLUnresolved

    public var errorDescription: String? {
        switch self {
        case .phpVersionNotInstalled(let version):
            return "PHP \(version) is not installed. Install it first, then retry the restore."
        case .sourceURLUnresolved:
            return "Could not determine the backup's original site address for search-replace."
        }
    }
}
