import Foundation

public final class RegisteredSiteWatcher: @unchecked Sendable {
    private final class Watch {
        let source: DispatchSourceFileSystemObject
        let fd: Int32
        var pending: DispatchWorkItem?
        init(source: DispatchSourceFileSystemObject, fd: Int32) { self.source = source; self.fd = fd }
    }

    private let debounce: TimeInterval
    private let queue = DispatchQueue(label: "com.ktstack.site-watcher")
    private var watches: [String: Watch] = [:]   // keyed by folder path

    public var onChange: (@Sendable (URL) -> Void)?

    public init(debounce: TimeInterval = 0.5) {
        self.debounce = debounce
    }

    public func watch(_ folders: [URL]) {
        queue.async { [self] in
            let wanted = Set(folders.map(\.path))
            for (path, w) in watches where !wanted.contains(path) {
                w.source.cancel(); watches[path] = nil
            }
            for folder in folders where watches[folder.path] == nil {
                arm(folder)
            }
        }
    }

    public func stop() {
        queue.async { [self] in cancelAllWatches() }
    }

    deinit { cancelAllWatches() }

    private func cancelAllWatches() {
        for (_, w) in watches { w.source.cancel() }
        watches.removeAll()
    }

    private func arm(_ folder: URL) {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue)
        let watch = Watch(source: source, fd: fd)
        source.setEventHandler { [weak self] in self?.scheduleCallback(folder) }
        source.setCancelHandler { close(fd) }
        watches[folder.path] = watch
        source.resume()
    }

   
    private func scheduleCallback(_ folder: URL) {
        guard let watch = watches[folder.path] else { return }
        watch.pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange?(folder) }
        watch.pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}
