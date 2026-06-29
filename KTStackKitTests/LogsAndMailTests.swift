import XCTest
@testable import KTStackKit

/// Unit tests for the Logs + Mail layers: severity parsing + ring buffer, log rotation, source
/// catalog, incremental tail, and Mailpit JSON decoding. Live HTTP/WKWebView is exercised manually.
final class LogsAndMailTests: XCTestCase {
    func testSeverityClassification() {
        XCTAssertEqual(LogLineStore.severity(of: "2026/06/11 [error] connect() failed"), .error)
        XCTAssertEqual(LogLineStore.severity(of: "[warn] low on workers"), .warning)
        XCTAssertEqual(LogLineStore.severity(of: "PHP Warning: undefined var"), .warning)
        XCTAssertEqual(LogLineStore.severity(of: "GET / 200 OK"), .info)
    }

    func testRingBufferEvictsOldestPastCapacity() {
        let store = LogLineStore(capacity: 3)
        store.append(["a", "b", "c", "d", "e"])
        let lines = store.snapshot()
        XCTAssertEqual(lines.map(\.text), ["c", "d", "e"])
        XCTAssertEqual(lines.map(\.id), [2, 3, 4]) // ids monotonic; the 2 oldest evicted
    }

    func testFilterIsCaseInsensitiveSubstring() {
        let store = LogLineStore()
        store.append(["GET /index.php", "POST /api", "error: boom"])
        XCTAssertEqual(store.filtered("api").map(\.text), ["POST /api"])
        XCTAssertEqual(store.filtered("ERROR").map(\.text), ["error: boom"])
        XCTAssertEqual(store.filtered("").count, 3)
    }

    func testRotationShiftsFilesAndTruncatesLive() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("nginx-error.log")
        try Data(repeating: 0x41, count: 2048).write(to: log) // 2KB
        let rotator = LogRotator(maxBytes: 1024, keep: 2)
        rotator.rotateIfNeeded(log)
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.appendingPathExtension("1").path))
        let liveSize = try (FileManager.default.attributesOfItem(atPath: log.path)[.size] as? Int) ?? -1
        XCTAssertEqual(liveSize, 0, "live log truncated after rotation")
    }

    func testRotationSkipsUnderThreshold() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("small.log")
        try Data(repeating: 0x41, count: 100).write(to: log)
        LogRotator(maxBytes: 1024).rotateIfNeeded(log)
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.appendingPathExtension("1").path))
    }

    func testCatalogListsCoreAndExistingSources() throws {
        let root = try tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppSupportPaths(root: root)
        try paths.ensureDirectoryTree()
        try Data().write(to: paths.serviceLog("redis")) // redis ran
        try Data().write(to: paths.siteAccessLog("demo.test")) // a site served
        let sources = LogCatalog(paths: paths).sources(siteDomains: ["demo.test"], phpVersions: ["8.4"])
        let ids = Set(sources.map(\.id))
        XCTAssertTrue(ids.contains("nginx-error")) // core, always listed
        XCTAssertTrue(ids.contains("php-8.4")) // active pool
        XCTAssertTrue(ids.contains("redis")) // exists
        XCTAssertTrue(ids.contains("site-demo.test-access")) // exists
        XCTAssertFalse(ids.contains("mysql")) // never ran → absent
    }

    /// Deterministic backfill coverage: on open, the reader emits the file's existing lines. The
    /// live-append path is driven by OS file-system events (flaky to unit-test) and is covered by
    /// real app usage instead.
    func testTailReaderBackfillsExistingLines() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("t.log")
        try "line1\nline2\n".write(to: log, atomically: true, encoding: .utf8)

        let gotBackfill = expectation(description: "backfill")
        let lock = NSLock()
        var collected: [String] = []
        var fulfilled = false
        let reader = LogTailReader(url: log)
        reader.onLines = { batch in
            lock.lock()
            collected.append(contentsOf: batch)
            let done = collected.contains("line1") && collected.contains("line2") && !fulfilled
            if done { fulfilled = true }
            lock.unlock()
            if done { gotBackfill.fulfill() }
        }
        reader.start()
        wait(for: [gotBackfill], timeout: 3)
        reader.stop()
    }

    func testDecodeMessageList() throws {
        let json = """
        {"total":1,"unread":1,"count":1,"messages":[
          {"ID":"abc","MessageID":"x@mailpit","Read":false,
           "From":{"Name":"","Address":"app@demo.test"},
           "To":[{"Name":"","Address":"dev@ktstack.test"}],
           "Subject":"Hi","Created":"2026-06-11T21:24:34.473+07:00","Size":797,
           "Attachments":0,"Snippet":"hello"}]}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(MailListResponse.self, from: json)
        XCTAssertEqual(resp.unread, 1)
        let m = try XCTUnwrap(resp.messages.first)
        XCTAssertEqual(m.From?.Address, "app@demo.test")
        XCTAssertEqual(m.Subject, "Hi")
        XCTAssertNotNil(m.date, "RFC3339 fractional-seconds timestamp parses")
    }

    func testDecodeMessageDetail() throws {
        let json = """
        {"ID":"abc","From":{"Name":"App","Address":"app@demo.test"},
         "To":[{"Name":"","Address":"dev@ktstack.test"}],"Cc":null,
         "Subject":"Hi","Date":"2026-06-11T21:24:34.473+07:00",
         "Text":"plain","HTML":"<h1>hi</h1>","Attachments":[]}
        """.data(using: .utf8)!
        let d = try JSONDecoder().decode(MailDetail.self, from: json)
        XCTAssertEqual(d.From?.display, "App <app@demo.test>")
        XCTAssertEqual(d.HTML, "<h1>hi</h1>")
        XCTAssertEqual(d.Text, "plain")
    }

    private func tempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kd-lm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
