import XCTest
@testable import KTStackKit

final class ArchChecksumGateTests: XCTestCase {
    private let realSHA = "e8bf680f8372a9cd4fab38b120753fef1ffb8980d8b5554d64c7186e671616b0"

    func testIsResolvedAcceptsOnlyRealHexChecksums() {
        XCTAssertTrue(ChecksumVerifier.isResolved(realSHA))
        XCTAssertTrue(ChecksumVerifier.isResolved(realSHA.uppercased()))

        XCTAssertFalse(ChecksumVerifier.isResolved(nil))
        XCTAssertFalse(ChecksumVerifier.isResolved(""))
        XCTAssertFalse(ChecksumVerifier.isResolved("PENDING_x86_64_MONGOD_SHA256"))
        XCTAssertFalse(ChecksumVerifier.isResolved("PENDING_x86_64_PHP"))
        XCTAssertFalse(ChecksumVerifier.isResolved(String(realSHA.dropLast())))
        XCTAssertFalse(ChecksumVerifier.isResolved(realSHA + "a"))
        XCTAssertFalse(ChecksumVerifier.isResolved(String(repeating: "z", count: 64)))
    }

    func testMongoEngineAndToolsResolveBothArches() throws {
        let mongo = try XCTUnwrap(ServiceBinaryCatalog.manifest.first { $0.kind == .mongodb })
        for arch in ["arm64", "x86_64"] {
            XCTAssertTrue(ChecksumVerifier.isResolved(mongo.sha256ByArch[arch]), "mongod \(arch)")
        }

        let tools = MongoToolsCatalog.pinned
        for arch in ["arm64", "x86_64"] {
            XCTAssertTrue(ChecksumVerifier.isResolved(tools.sha256ByArch[arch]), "mongo tools \(arch)")
        }
    }

    func testPHPExtensionReleaseGatesByCurrentArchChecksum() {
        let currentArch = RuntimeCatalog.arch
        let otherArch = currentArch == "arm64" ? "x86_64" : "arm64"

        let supported = PHPExtensionRelease(extID: "redis", phpVersion: "8.3",
                                            sha256ByArch: [currentArch: realSHA])
        XCTAssertTrue(supported.supportsCurrentArch)
        XCTAssertEqual(supported.url.lastPathComponent, "php-ext-redis-8.3-\(currentArch).tar.gz")

        let foreignArchOnly = PHPExtensionRelease(extID: "redis", phpVersion: "8.3",
                                                  sha256ByArch: [otherArch: realSHA])
        XCTAssertFalse(foreignArchOnly.supportsCurrentArch,
                       "an extension without a current-arch checksum must not gate as available")
    }

    func testShippedDatabaseEnginesHaveRealChecksumsForBothArches() {
        for kind in [ServiceKind.mysql, .postgres, .redis] {
            let release = ServiceBinaryCatalog.manifest.first { $0.kind == kind }
            XCTAssertNotNil(release, "\(kind) missing from manifest")
            XCTAssertTrue(ChecksumVerifier.isResolved(release?.sha256ByArch["arm64"]), "\(kind) arm64")
            XCTAssertTrue(ChecksumVerifier.isResolved(release?.sha256ByArch["x86_64"]), "\(kind) x86_64")
        }
    }
}
