import XCTest
@testable import KTStackKit

final class PHPFrameworkDetectorTests: XCTestCase {
    private let detector = PHPFrameworkDetector()
    private let fm = FileManager.default

    private func tempFolder(_ name: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ folder: URL, _ name: String) throws {
        try "<?php".write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testDetectsLaravelByArtisan() throws {
        let folder = tempFolder("laravel")
        defer { try? fm.removeItem(at: folder) }
        try touch(folder, "artisan")
        XCTAssertEqual(detector.detect(siteAt: folder), .laravel)
    }

    func testDetectsWordPressByConfigAtRoot() throws {
        let folder = tempFolder("wp")
        defer { try? fm.removeItem(at: folder) }
        try touch(folder, "wp-config.php")
        XCTAssertEqual(detector.detect(siteAt: folder), .wordpress)
    }

    func testDetectsWordPressByLoaderInDocroot() throws {
        let folder = tempFolder("wp-docroot")
        defer { try? fm.removeItem(at: folder) }
        let pub = folder.appendingPathComponent("public", isDirectory: true)
        try fm.createDirectory(at: pub, withIntermediateDirectories: true)
        try touch(pub, "wp-load.php")
        XCTAssertEqual(detector.detect(siteAt: folder, docroot: pub), .wordpress)
    }

    func testLaravelTakesPrecedenceOverWordPress() throws {
        let folder = tempFolder("both")
        defer { try? fm.removeItem(at: folder) }
        try touch(folder, "artisan")
        try touch(folder, "wp-config.php")
        XCTAssertEqual(detector.detect(siteAt: folder), .laravel)
    }

    func testPlainPHPWhenNoFrameworkMarkers() throws {
        let folder = tempFolder("plain")
        defer { try? fm.removeItem(at: folder) }
        try touch(folder, "index.php")
        XCTAssertEqual(detector.detect(siteAt: folder), .plain)
    }
}
