import XCTest
@testable import KDWarmKit

/// Security-invariant tests for the privileged DNS boundary: the helper and the sudo fallback must
/// re-validate every TLD/domain that reaches a root operation, because the app-side check is a UX
/// gate, not a trust boundary. Covers path-traversal, dnsmasq-config (newline) injection, and the
/// execution chokepoints that render attacker-influenced values into root-run scripts.
final class SecurityHardeningTests: XCTestCase {

    // MARK: - DNSConstants.isValidTLD / validatedTLD

    func testValidTLDAcceptsNormalTLDs() {
        for t in ["test", "localhost", "internal", "dev.local", "a", "x1"] {
            XCTAssertTrue(DNSConstants.isValidTLD(t), "\(t) should be valid")
        }
    }

    func testValidTLDRejectsPathTraversal() {
        for t in ["../../etc/sudoers", "../../Library/LaunchDaemons/com.evil", "a/b", "..", "/etc"] {
            XCTAssertFalse(DNSConstants.isValidTLD(t), "\(t) must be rejected (traversal)")
        }
    }

    /// The load-bearing case: a newline lets a `tld` inject extra dnsmasq directives into the root
    /// daemon config (the heredoc body can't be shell-quoted). Swift's `^…$` matches before a trailing
    /// newline, so the validator MUST reject control chars explicitly, not rely on the regex alone.
    func testValidTLDRejectsNewlineInjection() {
        for t in ["test\nserver=8.8.8.8", "test\nconf-file=/etc/attacker.conf", "test\n", "test\r", "te\nst"] {
            XCTAssertFalse(DNSConstants.isValidTLD(t), "newline-bearing TLD must be rejected: \(t.debugDescription)")
        }
    }

    func testValidTLDRejectsControlAndShape() {
        for t in ["", "TEST", "Test", ".test", "test.", "a;b", "a b", " test", "te..st", "-test", "test-", "tëst"] {
            XCTAssertFalse(DNSConstants.isValidTLD(t), "\(t.debugDescription) must be rejected")
        }
    }

    func testValidatedTLDThrowsOnInvalidReturnsOnValid() throws {
        XCTAssertThrowsError(try DNSConstants.validatedTLD("../x"))
        XCTAssertThrowsError(try DNSConstants.validatedTLD("test\nserver=x"))
        XCTAssertEqual(try DNSConstants.validatedTLD("test"), "test")
    }

    func testResolverPathCheckedRejectsEscapeAllowsValid() throws {
        XCTAssertThrowsError(try DNSConstants.resolverPathChecked(for: "../../etc/sudoers"))
        XCTAssertThrowsError(try DNSConstants.resolverPathChecked(for: "test\n"))
        XCTAssertEqual(try DNSConstants.resolverPathChecked(for: "test"), "/etc/resolver/test")
    }

    // MARK: - SudoFallbackInstaller execution chokepoints (root-run paths)

    /// `writeScripts` is the chokepoint for install/uninstall/reset run paths — it must refuse a
    /// malicious stored TLD before staging a root script that renders it into a heredoc.
    func testSudoFallbackWriteScriptsRejectsMaliciousTLD() {
        let bad = SudoFallbackInstaller(bundledDnsmasq: URL(fileURLWithPath: "/tmp/dnsmasq"),
                                        tld: "test\nserver=evil")
        XCTAssertThrowsError(try bad.writeScripts(to: SudoFallbackInstaller.freshStagingDir()))
    }

    func testSudoFallbackWriteScriptsAcceptsValidTLD() throws {
        let dir = SudoFallbackInstaller.freshStagingDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ok = SudoFallbackInstaller(bundledDnsmasq: URL(fileURLWithPath: "/tmp/dnsmasq"), tld: "test")
        XCTAssertNoThrow(try ok.writeScripts(to: dir))
    }

    /// `runSetTLDWithAdminPrivileges` takes fresh untrusted `old`/`new` — both must be validated
    /// before any script is staged/run (the throw happens before the admin prompt).
    func testSudoFallbackSetTLDRejectsMaliciousInput() {
        let inst = SudoFallbackInstaller(bundledDnsmasq: URL(fileURLWithPath: "/tmp/dnsmasq"), tld: "test")
        XCTAssertThrowsError(try inst.runSetTLDWithAdminPrivileges(old: "test", new: "../../etc/x"))
        XCTAssertThrowsError(try inst.runSetTLDWithAdminPrivileges(old: "x\ninject", new: "test"))
    }

    // MARK: - On-demand binary signature check at launch

    func testSignatureVerifierPassesOnSignedSystemBinary() {
        // /bin/ls is Apple-signed → a valid, strict signature.
        XCTAssertTrue(BinaryStager.verifySignature(at: URL(fileURLWithPath: "/bin/ls")))
    }

    func testSignatureVerifierFailsOnUnsignedFile() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-unsigned-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: tmp)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        XCTAssertFalse(BinaryStager.verifySignature(at: tmp), "an unsigned file must fail --verify --strict")
    }

    /// The launch path must refuse to bootstrap a launchd job whose binary fails its signature check
    /// (on-demand binaries lost quarantine at install + live in a writable dir → re-verify at launch).
    func testLaunchdRunnerRefusesUnsignedBinary() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-badbin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("not a real binary".utf8).write(to: tmp)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)

        let paths = AppSupportPaths(root: URL(fileURLWithPath: "/tmp/kdwarm-sec-test"))
        let runner = LaunchdServiceRunner(
            kind: .redis, label: "com.kdwarm.sec-test",
            preflightPorts: [], probe: .tcp(port: 1), agents: LaunchAgentManager(paths: paths))
        let spec = LaunchAgentSpec(label: "com.kdwarm.sec-test", programArguments: [tmp.path],
                                   workingDirectory: "/tmp", stdoutPath: "/tmp/x.log", stderrPath: "/tmp/x.log")
        do {
            try await runner.start(spec: spec)
            XCTFail("start must throw before bootstrapping an unsigned binary")
        } catch {
            // expected — signature check throws before any launchd op
        }
    }

    // MARK: - Download transport hardening (HTTPS-only + redirect)

    func testRequireHTTPSRejectsNonHTTPS() {
        XCTAssertThrowsError(try RuntimeDownloader.requireHTTPS(URL(string: "http://example.com/x.tgz")!))
        XCTAssertThrowsError(try RuntimeDownloader.requireHTTPS(URL(fileURLWithPath: "/tmp/x.tgz")))
        XCTAssertNoThrow(try RuntimeDownloader.requireHTTPS(URL(string: "https://example.com/x.tgz")!))
    }

    func testRedirectAllowedOnlyForHTTPS() {
        XCTAssertTrue(RuntimeDownloader.isRedirectAllowed(to: URL(string: "https://cdn.example.com/x")!))
        XCTAssertFalse(RuntimeDownloader.isRedirectAllowed(to: URL(string: "http://cdn.example.com/x")!))
    }

    /// Regression guard: the HTTPS-only download policy must not break real installs — every pinned
    /// manifest URL (runtimes + DB engines) is already HTTPS.
    func testAllManifestURLsAreHTTPS() {
        for r in RuntimeCatalog.manifest {
            XCTAssertEqual(r.url.scheme, "https", "\(r.id) must be HTTPS")
        }
        for r in ServiceBinaryCatalog.manifest {
            XCTAssertEqual(r.url.scheme, "https", "\(r.id) must be HTTPS")
        }
    }
}
