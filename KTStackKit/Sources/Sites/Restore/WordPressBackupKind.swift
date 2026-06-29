import Foundation

public enum WordPressBackupKind: String, Sendable, Equatable, CaseIterable {
    case duplicatorZip
    case aioWpress

    public var label: String {
        switch self {
        case .duplicatorZip: "Duplicator"
        case .aioWpress: "All-in-One WP Migration"
        }
    }

    public var fileExtension: String {
        switch self {
        case .duplicatorZip: "zip"
        case .aioWpress: "wpress"
        }
    }
}
