import XCTest
@testable import KTStackKit

final class DNSConstantsTests: XCTestCase {
    func testResolverContentsRoutesToLoopback() {
        XCTAssertTrue(DNSConstants.resolverContents.contains("nameserver 127.0.0.1"))
        XCTAssertTrue(DNSConstants.resolverContents.contains("port 53"))
    }

    func testDnsmasqConfAnswersOnlyConfiguredTLD() {
        let conf = DNSConstants.dnsmasqConf(for: "test")
        XCTAssertTrue(conf.contains("address=/.test/127.0.0.1"))
        XCTAssertTrue(conf.contains("listen-address=127.0.0.1"))
        XCTAssertTrue(conf.contains("no-resolv")) // no upstream — only answers the configured TLD
        // A custom TLD wildcards that TLD instead.
        XCTAssertTrue(DNSConstants.dnsmasqConf(for: "home.arpa").contains("address=/.home.arpa/127.0.0.1"))
    }

    func testDaemonPlistReferencesBinaryAndLabel() {
        let plist = DNSConstants.daemonPlist
        XCTAssertTrue(plist.contains("<string>com.ktstack.dnsmasq</string>"))
        XCTAssertTrue(plist.contains(DNSConstants.dnsmasqBinaryPath))
        XCTAssertTrue(plist.contains("--conf-file=\(DNSConstants.dnsmasqConfPath)"))
    }

    func testRootPathsAreSystemOwnedNotUserWritable() {
        XCTAssertEqual(DNSConstants.resolverPath(for: "test"), "/etc/resolver/test")
        XCTAssertTrue(DNSConstants.daemonPlistPath.hasPrefix("/Library/LaunchDaemons/"))
        XCTAssertTrue(DNSConstants.supportDir.hasPrefix("/Library/"))
    }
}

final class HelperIdentityTests: XCTestCase {
    func testDevBuildHasNoSigningIdentityAndIdentifierOnlyRequirement() {
        // The dev/ad-hoc build ships with an empty Team ID.
        XCTAssertFalse(HelperIdentity.hasSigningIdentity)
        XCTAssertEqual(HelperIdentity.clientRequirement, "identifier \"com.ktstack.app\"")
        XCTAssertEqual(HelperIdentity.helperRequirement, "identifier \"com.ktstack.helper\"")
    }

    func testIdentifiersAreConsistent() {
        XCTAssertEqual(HelperIdentity.machServiceName, "com.ktstack.helper")
        XCTAssertEqual(HelperIdentity.appBundleID, "com.ktstack.app")
    }
}

final class Port53ConflictTests: XCTestCase {
    func testForeignProcessIsNamedConflictOwnDnsmasqIsNot() {
        XCTAssertFalse(Port53ConflictDetector.isOwn("mDNSResponder"))
        XCTAssertTrue(Port53ConflictDetector.isOwn("dnsmasq"))
        XCTAssertTrue(Port53ConflictDetector.isOwn("com.ktstack.dnsmasq"))
        XCTAssertTrue(Port53ConflictDetector.message(for: "Herd Helper").contains("Herd"))
        XCTAssertTrue(Port53ConflictDetector.message(for: "named").contains("53"))
    }
}

final class SudoFallbackInstallerTests: XCTestCase {
    private let installer = SudoFallbackInstaller(bundledDnsmasq: URL(fileURLWithPath: "/tmp/dnsmasq"))

    func testInstallScriptCoversAllRootStepsWithShellQuoting() {
        let s = installer.installScript()
        // Interpolated paths are single-quote-escaped (no raw injection into the root shell).
        XCTAssertTrue(s.contains("cp '/tmp/dnsmasq' '\(DNSConstants.dnsmasqBinaryPath)'"))
        XCTAssertTrue(s.contains("address=/.test/127.0.0.1"))
        XCTAssertTrue(s.contains("launchctl bootstrap system '\(DNSConstants.daemonPlistPath)'"))
        XCTAssertTrue(s.contains("cat > '\(DNSConstants.resolverPath(for: "test"))'"))
    }

    func testShellQuoteEscapesSingleQuotes() {
        XCTAssertEqual(SudoFallbackInstaller.shellQuote("/a/b"), "'/a/b'")
        XCTAssertEqual(SudoFallbackInstaller.shellQuote("a'b"), "'a'\\''b'")
    }

    func testResetScriptUninstallsThenInstallsInOneInvocation() {
        let s = installer.resetScript()
        let bootout = s.range(of: "launchctl bootout")!
        let bootstrap = s.range(of: "launchctl bootstrap")!
        XCTAssertTrue(bootout.lowerBound < bootstrap.lowerBound, "reset must uninstall before install")
    }

    func testUninstallScriptReversesEverything() {
        let s = installer.uninstallScript()
        XCTAssertTrue(s.contains("launchctl bootout system/com.ktstack.dnsmasq"))
        XCTAssertTrue(s.contains("rm -f '\(DNSConstants.resolverPath(for: "test"))'"))
    }

    func testWriteScriptsProducesExecutableFiles() throws {
        let dir = SudoFallbackInstaller.freshStagingDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let scripts = try installer.writeScripts(to: dir)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scripts.install.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scripts.uninstall.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scripts.reset.path))
    }
}
