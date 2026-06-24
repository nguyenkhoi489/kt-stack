import Foundation

public enum WordPressBackupKind: String, Sendable, Equatable, CaseIterable {
    case duplicatorZip
    case aioWpress

    public var label: String {
        switch self {
        case .duplicatorZip: return "Duplicator"
        case .aioWpress: return "All-in-One WP Migration"
        }
    }

    public var fileExtension: String {
        switch self {
        case .duplicatorZip: return "zip"
        case .aioWpress: return "wpress"
        }
    }
}
