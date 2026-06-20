import Foundation

protocol SessionConnection: Sendable {
    var isLive: Bool { get }
    func runText(_ sql: String) async throws -> QueryResult
    func runSelect(_ statement: DMLStatement) async throws -> QueryResult
    func shutdown() async
}

public actor ConnectionSession {

    private let factory: @Sendable () async throws -> SessionConnection
    private var connection: SessionConnection?
    private var gateHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(factory: @escaping @Sendable () async throws -> SessionConnection) {
        self.factory = factory
    }

    public func warmUp() async throws {
        try await withConnection { _ in }
    }

    public func shutdown() async {
        await acquire()
        defer { release() }
        await connection?.shutdown()
        connection = nil
    }

    func runText(_ sql: String) async throws -> QueryResult {
        try await withConnection { try await $0.runText(sql) }
    }

    func runSelect(_ statement: DMLStatement) async throws -> QueryResult {
        try await withConnection { try await $0.runSelect(statement) }
    }

    private func withConnection<R>(_ body: (SessionConnection) async throws -> R) async throws -> R {
        await acquire()
        defer { release() }
        let live = try await ensureConnection()
        return try await body(live)
    }

    private func ensureConnection() async throws -> SessionConnection {
        if let connection, connection.isLive { return connection }
        if let stale = connection { await stale.shutdown() }
        let fresh = try await factory()
        connection = fresh
        return fresh
    }

    private func acquire() async {
        if !gateHeld {
            gateHeld = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            gateHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
