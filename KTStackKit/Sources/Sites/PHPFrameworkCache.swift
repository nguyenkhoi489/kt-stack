import Foundation

public actor PHPFrameworkCache {
    public static let shared = PHPFrameworkCache()

    private var cache: [String: PHPFramework] = [:]
    private let detector = PHPFrameworkDetector()

    private init() {}

    public func framework(path: String, docroot: String) -> PHPFramework {
        if let cached = cache[path] { return cached }
        let result = detector.detect(
            siteAt: URL(fileURLWithPath: path),
            docroot: URL(fileURLWithPath: docroot)
        )
        cache[path] = result
        return result
    }
}
