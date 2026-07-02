import Foundation

public final class LogTailReader: @unchecked Sendable {
    public var onLines: (@Sendable ([String]) -> Void)?

    private let url: URL
    private let backfillBytes: Int
    private let queue = DispatchQueue(label: "com.ktstack.logtail")
    private var handle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var offset: UInt64 = 0
    private var partial = ""
    private var reopenTimer: DispatchSourceTimer?

    public init(url: URL, backfillBytes: Int = 256 * 1024) {
        self.url = url
        self.backfillBytes = backfillBytes
    }

    public func start() {
        queue.async { [weak self] in self?.open() }
    }

    public func stop() {
        queue.async { [weak self] in self?.teardown() }
    }

    private func open() {
        teardown()

        let fd = Darwin.open(url.path, O_RDONLY)
        guard fd >= 0 else {
            scheduleReopen()
            return
        }
        let fh = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        handle = fh
        let size = (try? fh.seekToEnd()) ?? 0

        let start = size > UInt64(backfillBytes) ? size - UInt64(backfillBytes) : 0
        try? fh.seek(toOffset: start)
        let data = (try? fh.readToEnd()) ?? Data()
        offset = (try? fh.offset()) ?? size
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }
        emit(text, isBackfill: true)
        beginMonitoring(fd: fd)
    }

    private func beginMonitoring(fd: Int32) {
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .link], queue: queue
        )
        src.setEventHandler { [weak self] in self?.handleEvent(src.data) }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    private func handleEvent(_ mask: DispatchSource.FileSystemEvent) {
        if mask.contains(.delete) || mask.contains(.rename) || mask.contains(.link) {
            open()
            return
        }
        guard let fh = handle else { return }
        let size = (try? fh.seekToEnd()) ?? 0
        // File shrank under us (rotated or truncated), so restart from the top instead of seeking
        // past EOF and stalling with no new lines.
        if size < offset { offset = 0 }
        try? fh.seek(toOffset: offset)
        let data = (try? fh.readToEnd()) ?? Data()
        offset = (try? fh.offset()) ?? offset
        emit(String(decoding: data, as: UTF8.self), isBackfill: false)
    }

    private func emit(_ chunk: String, isBackfill _: Bool) {
        guard !chunk.isEmpty else { return }
        let combined = partial + chunk
        var lines = combined.components(separatedBy: "\n")
        partial = lines.removeLast()
        let complete = lines.filter { !$0.isEmpty }
        guard !complete.isEmpty else { return }
        onLines?(complete)
    }

    private func scheduleReopen() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1.0)
        t.setEventHandler { [weak self] in self?.reopenTimer = nil; self?.open() }
        reopenTimer = t
        t.resume()
    }

    private func teardown() {
        reopenTimer?.cancel(); reopenTimer = nil
        source?.cancel(); source = nil
        handle = nil
        offset = 0; partial = ""
    }
}
