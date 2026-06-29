import Foundation
import NIOCore
import NIOPosix

public final class EventLoopProvider: @unchecked Sendable {
    public static let shared = EventLoopProvider()

    public enum ProviderError: Error {
        case shutDown

        case shutdownTimedOut
    }

    public static let shutdownDeadline: Duration = .seconds(3)

    private let lock = NSLock()
    private var loopGroup: MultiThreadedEventLoopGroup?
    private var didShutdown = false

    private init() {}

    public func group() throws -> any EventLoopGroup {
        lock.lock(); defer { lock.unlock() }
        if didShutdown { throw ProviderError.shutDown }
        if let loopGroup { return loopGroup }
        let created = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        loopGroup = created
        return created
    }

    public func shutdown() async throws {
        lock.lock()
        let existing = loopGroup
        loopGroup = nil
        didShutdown = true
        lock.unlock()
        guard let existing else { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await existing.shutdownGracefully() }
            group.addTask {
                try await Task.sleep(for: Self.shutdownDeadline)
                throw ProviderError.shutdownTimedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}
