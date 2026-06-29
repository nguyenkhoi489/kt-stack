import XCTest
@testable import KTStackKit

/// Configurable-TLD derivation: resolver path + dnsmasq wildcard per TLD, the sudo `setTLD` reconcile
/// script (remove-old-then-install-new), and registry validation against the injected TLD.
final class TLDResolutionTests: XCTestCase {
    private let installer = SudoFallbackInstaller(bundledDnsmasq: URL(fileURLWithPath: "/tmp/dnsmasq"), tld: "internal")

    func testResolverPathDerivesPerTLD() {
        XCTAssertEqual(DNSConstants.resolverPath(for: "test"), "/etc/resolver/test")
        XCTAssertEqual(DNSConstants.resolverPath(for: "home.arpa"), "/etc/resolver/home.arpa")
    }

    func testDnsmasqConfWildcardsConfiguredTLD() {
        XCTAssertTrue(DNSConstants.dnsmasqConf(for: "internal").contains("address=/.internal/127.0.0.1"))
        XCTAssertFalse(DNSConstants.dnsmasqConf(for: "internal").contains("address=/.test/"))
    }

    func testSudoInstallScriptUsesConfiguredTLD() {
        let s = installer.installScript()
        XCTAssertTrue(s.contains("cat > '/etc/resolver/internal'"))
        XCTAssertTrue(s.contains("address=/.internal/127.0.0.1"))
    }

    func testSetTLDScriptRemovesOldBeforeInstallingNewThenFlushes() {
        let s = installer.setTLDScript(old: "test", new: "localhost")
        let rm = try? XCTUnwrap(s.range(of: "rm -f '/etc/resolver/test'"))
        let writeNew = try? XCTUnwrap(s.range(of: "cat > '/etc/resolver/localhost'"))
        XCTAssertNotNil(rm); XCTAssertNotNil(writeNew)
        XCTAssertTrue(rm!.lowerBound < writeNew!.lowerBound, "old resolver must be removed before the new one is written")
        XCTAssertTrue(s.contains("dscacheutil -flushcache"))
    }

    func testSetTLDScriptNoOpWhenUnchangedSkipsRemoval() {
        let s = installer.setTLDScript(old: "test", new: "test")
        XCTAssertFalse(s.contains("rm -f '/etc/resolver/test'")) // nothing to orphan
        XCTAssertTrue(s.contains("cat > '/etc/resolver/test'"))
    }

    @MainActor
    func testRegistryValidatesAgainstInjectedTLD() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kd-tld-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = SiteRegistry(storeURL: dir.appendingPathComponent("sites.json"), tld: "localhost")
        XCTAssertThrowsError(try reg.validateDomain("app.test")) // wrong TLD for this registry
        XCTAssertNoThrow(try reg.validateDomain("app.localhost")) // matches the injected TLD
    }
}
