import Foundation

public enum PHPFramework: String, Sendable, Equatable {
    case wordpress
    case laravel
    case plain

    public var label: String {
        switch self {
        case .wordpress: return "WordPress"
        case .laravel:   return "Laravel"
        case .plain:     return "PHP"
        }
    }
}

public struct PHPFrameworkDetector: Sendable {
    private let laravel = LaravelSiteProbe()
    private let wordpress = WordPressSiteProbe()

    public init() {}

    public func detect(siteAt folder: URL, docroot: URL? = nil,
                       fileManager: FileManager = .default) -> PHPFramework {
        if laravel.isLaravel(siteAt: folder, fileManager: fileManager) { return .laravel }
        if wordpress.isWordPress(siteAt: folder, docroot: docroot, fileManager: fileManager) { return .wordpress }
        return .plain
    }
}
