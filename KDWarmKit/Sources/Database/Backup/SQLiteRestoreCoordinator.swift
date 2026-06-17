import Foundation

/// `SQLiteDriver` opens a fresh `DatabaseQueue` per call with no shared closable connection, so there
/// is no driver handle to close during a restore. This actor serializes restores by file path so a
/// file swap never overlaps another restore of the same database; combined with an atomic
/// `replaceItemAt`, a concurrent driver read sees either the old or the new file, never a torn one.
public actor SQLiteRestoreCoordinator {
    public static let shared = SQLiteRestoreCoordinator()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var held: Set<String> = []
    private var waiters: [String: [Waiter]] = [:]

    public init() {}

    public func withExclusiveAccess<T: Sendable>(
        to path: String, _ body: @Sendable () async throws -> T) async throws -> T {
        try await acquire(path)
        do {
            let result = try await body()
            release(path)
            return result
        } catch {
            release(path)
            throw error
        }
    }

    /// Cancellation contract: a Task cancelled while waiting on a held path must NOT leave its
    /// continuation un-resumed or future callers deadlock forever. Drop the waiter entry on cancel
    /// and propagate `CancellationError`.
    private func acquire(_ path: String) async throws {
        if !held.contains(path) {
            held.insert(path)
            return
        }
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters[path, default: []].append(Waiter(id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task { await self.dropWaiter(id: waiterID, path: path) }
        }
    }

    private func dropWaiter(id: UUID, path: String) {
        guard var queue = waiters[path] else { return }
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let waiter = queue.remove(at: index)
        waiters[path] = queue.isEmpty ? nil : queue
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func release(_ path: String) {
        if var queue = waiters[path], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[path] = queue.isEmpty ? nil : queue
            next.continuation.resume()
        } else {
            held.remove(path)
        }
    }
}
