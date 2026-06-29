import Combine
import Foundation

@MainActor
public final class LogTailController: ObservableObject {
    @Published public private(set) var lines: [LogLine] = []
    @Published public var filter = "" {
        didSet { recompute() }
    }

    @Published public var isLive = true
    @Published public private(set) var currentSourceID: String?

    private let store: LogLineStore
    private var reader: LogTailReader?
    private var currentSourceURL: URL?

    public init(capacity: Int = 5000) {
        store = LogLineStore(capacity: capacity)
    }

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

    private func recompute() {
        lines = store.filtered(filter)
    }
}
