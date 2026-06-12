import XCTest
@testable import KDWarmKit

final class SiteScannerTests: XCTestCase {
    private let fm = FileManager.default
    private let scanner = SiteScanner()

    private func tempRoot() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-scan-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func mkdir(_ root: URL, _ name: String) -> URL {
        let u = root.appendingPathComponent(name, isDirectory: true)
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testScanListsDepth1DirsWithProposedDomainAndDetectedType() throws {
        let root = tempRoot(); defer { try? fm.removeItem(at: root) }
        let shop = mkdir(root, "shop")
        let pub = shop.appendingPathComponent("public", isDirectory: true)
        try fm.createDirectory(at: pub, withIntermediateDirectories: true)
        try "<?php".write(to: pub.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        mkdir(root, "blog")   // no markers → static

        let result = scanner.scan(root: root, tld: "test")
        XCTAssertEqual(result.count, 2)
        let shopRow = try XCTUnwrap(result.first { $0.folder.lastPathComponent == "shop" })
        XCTAssertEqual(shopRow.proposedDomain, "shop.test")
        XCTAssertEqual(shopRow.type, .php)
        XCTAssertEqual(shopRow.docroot.lastPathComponent, "public")
        XCTAssertFalse(shopRow.alreadyRegistered)
    }

    func testProposedDomainUsesConfiguredTLD() {
        let root = tempRoot(); defer { try? fm.removeItem(at: root) }
        mkdir(root, "myapp")
        XCTAssertEqual(scanner.scan(root: root, tld: "localhost").first?.proposedDomain, "myapp.localhost")
    }

    func testSkipsDotfoldersLooseFilesAndSymlinks() throws {
        let root = tempRoot(); defer { try? fm.removeItem(at: root) }
        mkdir(root, "real")
        mkdir(root, ".hidden")
        try "x".write(to: root.appendingPathComponent("loosefile.txt"), atomically: true, encoding: .utf8)
        let target = mkdir(root, "target")
        try fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: target)

        let names = scanner.scan(root: root).map(\.folder.lastPathComponent).sorted()
        XCTAssertEqual(names, ["real", "target"])   // .hidden, loosefile.txt, and the symlink are excluded
    }

    func testSkipsFileSystemPackages() {
        let root = tempRoot(); defer { try? fm.removeItem(at: root) }
        mkdir(root, "plain")
        mkdir(root, "Bundle.app")   // a directory with a package extension is treated as a package
        let names = scanner.scan(root: root).map(\.folder.lastPathComponent)
        XCTAssertTrue(names.contains("plain"))
        XCTAssertFalse(names.contains("Bundle.app"))
    }

    func testAlreadyRegisteredMatchesByCanonicalPath() {
        let root = tempRoot(); defer { try? fm.removeItem(at: root) }
        mkdir(root, "shop")
        // A non-standard but equivalent path form must still match (standardize + resolve symlinks).
        let messy = root.path + "/./shop"
        let row = scanner.scan(root: root, existingPaths: [messy]).first { $0.folder.lastPathComponent == "shop" }
        XCTAssertEqual(row?.alreadyRegistered, true)
    }

    func testMissingRootReturnsEmptyNotCrash() {
        let missing = URL(fileURLWithPath: "/tmp/kd-missing-\(UUID().uuidString)")
        XCTAssertTrue(scanner.scan(root: missing).isEmpty)
    }
}
