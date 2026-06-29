import Combine
import Foundation

@MainActor
public final class MailStore: ObservableObject {
    @Published public private(set) var messages: [MailSummary] = []
    @Published public private(set) var unread = 0
    @Published public private(set) var isReachable = false
    @Published public private(set) var detail: MailDetail?
    @Published public private(set) var lastError: String?
    @Published public var selectedID: String?

    private let client: MailpitClient
    private var pollTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?

    public init(client: MailpitClient = MailpitClient()) {
        self.client = client
    }

    public func startPolling(interval: TimeInterval = 3) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel(); pollTask = nil
    }

    public func refresh() async {
        do {
            let resp = try await client.list()
            messages = resp.messages
            unread = resp.unread
            isReachable = true
            lastError = nil
            if let sel = selectedID, !messages.contains(where: { $0.ID == sel }) {
                selectedID = nil; detail = nil
            }
        } catch {
            isReachable = false
            messages = []
        }
    }

    public func select(_ id: String) {
        selectedID = id
        detail = nil
        detailTask?.cancel()
        detailTask = Task { [weak self] in
            await self?.loadDetail(id)
        }
    }

    public func loadDetail(_ id: String) async {
        do {
            let d = try await client.detail(id: id)
            guard !Task.isCancelled, selectedID == id else { return }
            detail = d
        } catch {
            if !Task.isCancelled { lastError = error.localizedDescription }
        }
    }

    public func delete(_ id: String) {
        Task {
            do { try await client.delete(ids: [id]); if selectedID == id { selectedID = nil; detail = nil }; await refresh() }
            catch { lastError = error.localizedDescription }
        }
    }

    public func deleteAll() {
        Task {
            do { try await client.deleteAll(); selectedID = nil; detail = nil; await refresh() }
            catch { lastError = error.localizedDescription }
        }
    }

    public func rawURL(_ id: String) -> URL {
        client.rawURL(id: id)
    }
}
