import XCTest
@testable import KTStackKit

final class WPressArchiveReaderTests: XCTestCase {
    private var staging: URL!

    override func setUpWithError() throws {
        staging = try RestoreFixtureBuilder.makeTempDir("wpress-staging")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: staging)
    }

    func testRoundTripExtractsTreeAndMetadata() async throws {
        let archive = try RestoreFixtureBuilder.makeTempDir("wpress-archive")
            .appendingPathComponent("backup.wpress")
        let packageJSON = #"{"SiteURL":"https://old.example.com","WordPress":{"Version":"6.5.2"},"Database":{"Prefix":"wp_"}}"#
        try RestoreFixtureBuilder.writeWPress([
            .init(name: "database.sql", prefix: "", content: Data("INSERT siteurl https://old.example.com".utf8)),
            .init(name: "package.json", prefix: "", content: Data(packageJSON.utf8)),
            .init(name: "style.css", prefix: "wp-content/themes/x", content: Data("body{}".utf8)),
        ], to: archive)

        let payload = try await WPressArchiveReader().extract(archive, into: staging) { _ in }

        XCTAssertTrue(payload.isContentOnly)
        XCTAssertEqual(payload.kind, .aioWpress)
        XCTAssertEqual(payload.sourceURL, "https://old.example.com")
        XCTAssertEqual(payload.wpVersion, "6.5.2")
        XCTAssertEqual(payload.tablePrefix, "wp_")
        XCTAssertTrue(FileManager.default.fileExists(atPath: payload.sqlDump.path))
        let theme = payload.docroot.appendingPathComponent("wp-content/themes/x/style.css")
        XCTAssertEqual(try String(contentsOf: theme), "body{}")
    }

    func testPrefixFieldHexTailAfterNullIsIgnored() async throws {
        let archive = try RestoreFixtureBuilder.makeTempDir("wpress-hextail")
            .appendingPathComponent("hextail.wpress")
        var blob = Data()
        blob.append(field("database.sql", length: 255))
        blob.append(field("1", length: 14))
        blob.append(field("0", length: 12))
        blob.append(field(".", length: 4096))
        blob.append(Data("x".utf8))
        blob.append(field("style.css", length: 255))
        blob.append(field("2", length: 14))
        blob.append(field("0", length: 12))
        var prefixField = Array("wp-content\0".utf8)
        prefixField.append(contentsOf: repeatElement(0, count: 4096 - prefixField.count - 8))
        prefixField.append(contentsOf: Array("deadbeef".utf8))
        blob.append(Data(prefixField))
        blob.append(Data("hi".utf8))
        blob.append(Data(count: 4377))
        try blob.write(to: archive)

        let payload = try await WPressArchiveReader().extract(archive, into: staging) { _ in }
        let placed = payload.docroot.appendingPathComponent("wp-content/style.css")
        XCTAssertEqual(try String(contentsOf: placed), "hi")
        let topLevel = try FileManager.default.contentsOfDirectory(atPath: payload.docroot.path)
        XCTAssertEqual(Set(topLevel), ["wp-content"])
    }

    func testTraversalEntryIsRejected() async throws {
        let archive = try RestoreFixtureBuilder.makeTempDir("wpress-evil")
            .appendingPathComponent("evil.wpress")
        try RestoreFixtureBuilder.writeWPress([
            .init(name: "database.sql", prefix: "", content: Data("x".utf8)),
            .init(name: "evil.php", prefix: "../../escape", content: Data("<?php".utf8)),
        ], to: archive)

        do {
            _ = try await WPressArchiveReader().extract(archive, into: staging) { _ in }
            XCTFail("expected path escape rejection")
        } catch let error as RestoreArchiveError {
            XCTAssertEqual(error, .pathEscape("../../escape/evil.php"))
        }
        let escaped = staging.deletingLastPathComponent().appendingPathComponent("escape")
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
    }

    func testPremiumTrailerTreatedAsEnd() async throws {
        let archive = try RestoreFixtureBuilder.makeTempDir("wpress-trailer")
            .appendingPathComponent("signed.wpress")
        var blob = Data()
        blob.append(field("database.sql", length: 255))
        blob.append(field("5", length: 14))
        blob.append(field("0", length: 12))
        blob.append(field(".", length: 4096))
        blob.append(Data("hello".utf8))
        blob.append(field("", length: 255))
        blob.append(field("499160305", length: 14))
        blob.append(field("0", length: 12))
        var prefixTrailer = Array(String(repeating: "\0", count: 4088).utf8)
        prefixTrailer.append(contentsOf: Array("49935a5e".utf8))
        blob.append(Data(prefixTrailer))
        try blob.write(to: archive)

        let payload = try await WPressArchiveReader().extract(archive, into: staging) { _ in }
        XCTAssertEqual(try String(contentsOf: payload.sqlDump), "hello")
    }

    func testTruncatedContentHardFails() async throws {
        let archive = try RestoreFixtureBuilder.makeTempDir("wpress-trunc")
            .appendingPathComponent("trunc.wpress")
        var blob = Data()
        blob.append(field("database.sql", length: 255))
        blob.append(field("999", length: 14))
        blob.append(field("0", length: 12))
        blob.append(field("", length: 4096))
        blob.append(Data("short".utf8))
        try blob.write(to: archive)

        do {
            _ = try await WPressArchiveReader().extract(archive, into: staging) { _ in }
            XCTFail("expected desync rejection")
        } catch let error as RestoreArchiveError {
            guard case .archiveDesync = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    private func field(_ value: String, length: Int) -> Data {
        var bytes = Array(value.utf8.prefix(length))
        bytes.append(contentsOf: repeatElement(0, count: length - bytes.count))
        return Data(bytes)
    }
}
