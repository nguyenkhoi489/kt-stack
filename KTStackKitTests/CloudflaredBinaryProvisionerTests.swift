import XCTest
@testable import KTStackKit

final class CloudflaredBinaryProvisionerTests: XCTestCase {
    private func freshPaths() -> (AppSupportPaths, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-cf-\(UUID().uuidString)")
        return (AppSupportPaths(root: root), root)
    }

    func testToolsDirIsRootedAndInDirectoryTree() {
        let (paths, _) = freshPaths()
        XCTAssertTrue(paths.tools.path.hasPrefix(paths.root.path))
        XCTAssertTrue(
            paths.toolVersionDir("cloudflared", "2026.6.0").path
                .hasSuffix("tools/cloudflared/2026.6.0")
        )
        XCTAssertTrue(paths.allDirectories.contains(paths.tools))
    }

    func testBinaryURLShape() async {
        let (paths, _) = freshPaths()
        let provisioner = CloudflaredBinaryProvisioner(paths: paths)
        let url = await provisioner.binaryURL
        XCTAssertTrue(url.path.hasSuffix("tools/cloudflared/2026.6.0/cloudflared"))
    }

    func testReleaseDownloadURLIsHTTPSOnMirrorWithArchToken() {
        let release = CloudflaredBinaryProvisioner.release
        let url = release.downloadURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertTrue(url.absoluteString.hasPrefix(ServiceBinaryCatalog.releaseBaseURL.absoluteString))
        XCTAssertEqual(url.lastPathComponent, "cloudflared-2026.6.0-\(ServiceBinaryCatalog.arch).tar.gz")
    }

    func testPinnedChecksumMatchesArchAndIsHex() {
        let release = CloudflaredBinaryProvisioner.release
        let expected = ServiceBinaryCatalog.arch == "arm64" ? release.arm64SHA256 : release.x86_64SHA256
        XCTAssertEqual(release.sha256ForCurrentArch, expected)
        XCTAssertEqual(release.sha256ForCurrentArch.count, 64)
        XCTAssertTrue(release.sha256ForCurrentArch.allSatisfy(\.isHexDigit))
    }

    func testNotInstalledOnCleanPaths() async {
        let (paths, root) = freshPaths()
        defer { try? FileManager.default.removeItem(at: root) }
        let provisioner = CloudflaredBinaryProvisioner(paths: paths)
        let installed = await provisioner.isInstalled()
        XCTAssertFalse(installed)
        let binary = await provisioner.installedBinary()
        XCTAssertNil(binary)
    }

    func testEnsureInstalledDownloadsVerifiesAndIsIdempotent() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KTSTACK_NET_IT"] == "1",
            "Set KTSTACK_NET_IT=1 to download the cloudflared mirror over the network."
        )
        let (paths, root) = freshPaths()
        defer { try? FileManager.default.removeItem(at: root) }
        let provisioner = CloudflaredBinaryProvisioner(paths: paths)

        let binary = try await provisioner.ensureInstalled { _ in }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path))
        XCTAssertTrue(binary.path.hasSuffix("tools/cloudflared/2026.6.0/cloudflared"))

        let again = try await provisioner.ensureInstalled { _ in }
        XCTAssertEqual(binary, again)
    }
}
