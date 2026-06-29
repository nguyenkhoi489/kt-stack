import XCTest
@testable import KTStackKit

final class RegisteredSiteWatcherTests: XCTestCase {
    private var folder: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ktstack-watcher-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: folder)
    }

    func testReportsChangedFolderAfterDebounce() throws {
        let watcher = RegisteredSiteWatcher(debounce: 0.15)
        let fired = expectation(description: "onChange reports the watched folder")
        fired.assertForOverFulfill = false
        let watchedPath = folder.path
        watcher.onChange = { changed in
            if changed.path == watchedPath { fired.fulfill() }
        }

        watcher.watch([folder])
        Thread.sleep(forTimeInterval: 0.3)
        try "a".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        wait(for: [fired], timeout: 5)
        watcher.stop()
    }

    func testStopHaltsFurtherCallbacks() throws {
        let watcher = RegisteredSiteWatcher(debounce: 0.15)
        let beforeStop = expectation(description: "fires before stop")
        beforeStop.assertForOverFulfill = false
        watcher.onChange = { _ in beforeStop.fulfill() }

        watcher.watch([folder])
        Thread.sleep(forTimeInterval: 0.3)
        try "1".write(to: folder.appendingPathComponent("first.txt"), atomically: true, encoding: .utf8)
        wait(for: [beforeStop], timeout: 5)

        Thread.sleep(forTimeInterval: 0.3)
        watcher.stop()
        Thread.sleep(forTimeInterval: 0.3)

        let afterStop = expectation(description: "no callback after stop")
        afterStop.isInverted = true
        watcher.onChange = { _ in afterStop.fulfill() }
        try "2".write(to: folder.appendingPathComponent("second.txt"), atomically: true, encoding: .utf8)

        wait(for: [afterStop], timeout: 1.0)
    }
}
