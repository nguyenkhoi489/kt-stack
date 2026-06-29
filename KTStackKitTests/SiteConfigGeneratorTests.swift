import XCTest
@testable import KTStackKit

final class SiteConfigGeneratorTests: XCTestCase {
    private let fm = FileManager.default

    private func makePaths() -> (AppSupportPaths, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-gen-\(UUID().uuidString)", isDirectory: true)
        let paths = AppSupportPaths(root: root)
        try? paths.ensureDirectoryTree()
        return (paths, root)
    }

    private func site(_ domain: String, type: SiteType, version: String = "8.4") -> Site {
        Site(
            name: domain,
            path: "/tmp/\(domain)",
            docroot: "/tmp/\(domain)/public",
            domain: domain,
            phpVersion: version,
            type: type
        )
    }

    func testPHPVhostRoutesToVersionSocketStaticDoesNot() {
        let (paths, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        let gen = SiteConfigGenerator(paths: paths)

        let php = gen.vhostText(for: site("demo.test", type: .php, version: "8.4"), port: 80)
        XCTAssertTrue(php.contains("fastcgi_pass \"unix:\(paths.phpFpmSocket("8.4").path)\";"))
        XCTAssertTrue(php.contains("listen 0.0.0.0:80;"))

        let stat = gen.vhostText(for: site("html.test", type: .staticSite), port: 80)
        XCTAssertFalse(stat.contains("fastcgi_pass"))
        XCTAssertTrue(stat.contains("try_files $uri $uri/ =404;"))

        let node = gen.vhostText(for: site("node.test", type: .node), port: 80)
        XCTAssertFalse(node.contains("fastcgi_pass")) // node not served through PHP-FPM
    }

    func testRequiredVersionsOnlyCountsPHPSites() {
        let sites = [
            site("a.test", type: .php, version: "8.4"),
            site("b.test", type: .php, version: "8.1"),
            site("c.test", type: .staticSite, version: "8.4"),
        ]
        XCTAssertEqual(SiteConfigGenerator.requiredVersions(for: sites), ["8.4", "8.1"])
    }

    private func installPHP(_ versions: [String], in paths: AppSupportPaths) throws {
        for v in versions {
            let bin = paths.runtimeBin("php", v)
            try fm.createDirectory(at: bin, withIntermediateDirectories: true)
            fm.createFile(
                atPath: bin.appendingPathComponent("php-fpm").path,
                contents: Data(),
                attributes: [.posixPermissions: 0o755]
            )
        }
    }

    func testEffectivePHPVersionFallsBackWhenPinNotInstalled() throws {
        let (paths, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        try installPHP(["8.1"], in: paths)
        let gen = SiteConfigGenerator(paths: paths)
        XCTAssertEqual(gen.effectivePHPVersion("8.4"), "8.1") // pin missing → newest installed
        XCTAssertEqual(gen.effectivePHPVersion("8.1"), "8.1") // pin installed → unchanged
    }

    func testEffectivePHPVersionPicksNewestInstalledNumerically() throws {
        let (paths, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        try installPHP(["8.1", "8.3", "8.10"], in: paths) // 8.10 > 8.3 numerically (not lexically)
        let gen = SiteConfigGenerator(paths: paths)
        XCTAssertEqual(gen.effectivePHPVersion("8.4"), "8.10")
    }

    func testEffectivePHPVersionKeepsPinWhenNothingInstalled() {
        let (paths, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        let gen = SiteConfigGenerator(paths: paths)
        XCTAssertEqual(gen.effectivePHPVersion("8.4"), "8.4") // nothing to fall back to
    }

    func testPoolVersionsAndVhostRouteToFallback() throws {
        let (paths, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        try installPHP(["8.1"], in: paths)
        let gen = SiteConfigGenerator(paths: paths)
        let sites = [
            site("a.test", type: .php, version: "8.4"),
            site("b.test", type: .php, version: "8.1"),
        ]
        // Both PHP sites collapse onto the one installed version → a single 8.1 pool.
        XCTAssertEqual(gen.poolVersions(for: sites), ["8.1"])
        // The 8.4 site's vhost routes to the 8.1 fallback socket (so nginx has a live upstream).
        let vhost = gen.vhostText(for: site("a.test", type: .php, version: "8.4"), port: 80)
        XCTAssertTrue(
            vhost.contains("fastcgi_pass \"unix:\(paths.phpFpmSocket("8.1").path)\";"),
            "an 8.4 site must route to the 8.1 fallback socket"
        )
    }

    func testGenerateWritesIdempotentlyAndRemovesOrphans() throws {
        let (paths, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        let gen = SiteConfigGenerator(paths: paths)

        XCTAssertTrue(try gen.generate(sites: [site("demo.test", type: .php)])) // first write: changed
        XCTAssertFalse(try gen.generate(sites: [site("demo.test", type: .php)])) // identical: no change
        XCTAssertTrue(fm.fileExists(atPath: paths.vhost("demo.test").path))

        // Removing the site deletes its vhost (orphan cleanup).
        XCTAssertTrue(try gen.generate(sites: []))
        XCTAssertFalse(fm.fileExists(atPath: paths.vhost("demo.test").path))
    }

    func testSkippedSiteKeepsItsExistingVhost() throws {
        let (paths, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        let gen = SiteConfigGenerator(paths: paths)
        // Write a valid static site, then regenerate with the same site but an UNSAFE docroot
        // (skipped this pass). Its existing vhost must NOT be swept as an orphan.
        var s = site("keep.test", type: .staticSite)
        _ = try gen.generate(sites: [s])
        XCTAssertTrue(fm.fileExists(atPath: paths.vhost("keep.test").path))

        s.docroot = "/tmp/bad;rm -rf" // fails isSafePath → skipped
        _ = try gen.generate(sites: [s])
        XCTAssertTrue(
            fm.fileExists(atPath: paths.vhost("keep.test").path),
            "a registered-but-skipped site must keep its prior vhost (not orphaned)"
        )
    }

    func testGeneratePreservesActiveTunnelVhosts() throws {
        let (paths, root) = makePaths(); defer { try? fm.removeItem(at: root) }
        let tunnel = paths.vhost("tunnel-\(UUID().uuidString)")
        try "server {}".write(to: tunnel, atomically: true, encoding: .utf8)

        XCTAssertTrue(try SiteConfigGenerator(paths: paths).generate(sites: []))
        XCTAssertTrue(fm.fileExists(atPath: tunnel.path))
    }
}

final class BundledPHPTests: XCTestCase {
    func testFpmBinaryResolvesPerVersionRuntimeLayout() {
        let root = URL(fileURLWithPath: "/tmp/runtimes/php")
        let fpm84 = BundledPHP.fpmBinary(for: "8.4", php: root)
        XCTAssertEqual(fpm84.lastPathComponent, "php-fpm")
        XCTAssertTrue(fpm84.path.hasSuffix("php/8.4/bin/php-fpm"))
        XCTAssertTrue(BundledPHP.fpmBinary(for: "8.1", php: root).path.hasSuffix("php/8.1/bin/php-fpm"))
    }

    func testAvailableVersionsReflectsRuntimesOnDisk() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-php-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Install only 8.4 + 8.1 (with executable php-fpm); 7.4 dir exists but has no binary.
        for v in ["8.4", "8.1"] {
            let bin = root.appendingPathComponent("\(v)/bin", isDirectory: true)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            FileManager.default.createFile(
                atPath: bin.appendingPathComponent("php-fpm").path,
                contents: Data(),
                attributes: [.posixPermissions: 0o755]
            )
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("7.4/bin", isDirectory: true), withIntermediateDirectories: true
        )
        XCTAssertEqual(BundledPHP.availableVersions(php: root), ["8.1", "8.4"])
    }
}
