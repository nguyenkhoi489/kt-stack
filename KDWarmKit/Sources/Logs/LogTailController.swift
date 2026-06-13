import Foundation
import Combine

/// View-facing controller for the Logs viewer: owns the tail reader + ring buffer for the selected
/// source and publishes the (filtered) lines. `isLive` drives auto-scroll-to-tail in the view; the
/// tail keeps buffering regardless, so toggling live back on jumps to the latest without data loss.
@MainActor
public final class LogTailController: ObservableObject {
    @Published public private(set) var lines: [LogLine] = []
    @Published public var filter = "" { didSet { recompute() } }
    @Published public var isLive = true
    @Published public private(set) var currentSourceID: String?

    private let store: LogLineStore
    private var reader: LogTailReader?
    private var currentSourceURL: URL?

    public init(capacity: Int = 5_000) {
        self.store = LogLineStore(capacity: capacity)
    }

    /// Switch to a new source (or nil to clear). Stops the old tail, resets the buffer, starts anew.
    public func select(_ source: LogSource?) {
        reader?.stop()
        reader = nil
        store.clear()
        lines = []
        currentSourceID = source?.id
        currentSourceURL = source?.url
        guard let source else { return }
        let r = LogTailReader(url: source.url)
        r.onLines = { [weak self] batch in
            Task { @MainActor in self?.ingest(batch) }
        }
        reader = r
        r.start()
    }

    /// Empty the view AND the on-disk log file. Truncates via a separate handle (ftruncate keeps the
    /// inode) so a service writing in append mode keeps logging to the same file — never an atomic
    /// replace, which would orphan the writer's open fd. The tail reader resets its offset on the
    /// resulting shrink (see `LogTailReader`), so live tailing continues from the now-empty file.
    public func clear() {
        if let url = currentSourceURL, let fh = try? FileHandle(forWritingTo: url) {
            try? fh.truncate(atOffset: 0)
            try? fh.close()
        }
        store.clear()
        lines = []
    }

    private func ingest(_ batch: [String]) {
        store.append(batch)
        recompute()
    }

    private func recompute() { lines = store.filtered(filter) }
}
