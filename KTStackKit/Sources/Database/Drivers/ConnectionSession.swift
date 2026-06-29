import Foundation

protocol SessionConnection: Sendable {
    var isLive: Bool { get }
    func useDatabase(_ database: String) async throws
    func runText(_ sql: String) async throws -> QueryResult
    func runSelect(_ statement: DMLStatement) async throws -> QueryResult
    func shutdown() async
}

public actor ConnectionSession {
    private let factory: @Sendable () async throws -> SessionConnection
    private var connection: SessionConnection?
    private var gateHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var currentDatabase: String?
    private var databaseApplied = false
    private var epoch = 0
    private var cancelRequested = false

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
        databaseApplied = false
    }

    func runText(_ sql: String) async throws -> QueryResult {
        try await withConnection { try await $0.runText(sql) }
    }

    func runText(_ sql: String, database: String?) async throws -> QueryResult {
        await acquire()
        defer { release() }
        cancelRequested = false
        let live = try await ensureConnection()
        let myEpoch = epoch
        try await applyDatabaseIfNeeded(database, on: live)
        do {
            let result = try await live.runText(sql)
            cancelRequested = false
            return result
        } catch {
            if cancelRequested, myEpoch == epoch {
                cancelRequested = false
                throw DatabaseError.cancelled
            }
            throw error
        }
    }

    func runSelect(_ statement: DMLStatement) async throws -> QueryResult {
        try await withConnection { try await $0.runSelect(statement) }
    }

    func cancelInFlight() {
        cancelRequested = true
        let dead = connection
        connection = nil
        databaseApplied = false
        Task { await dead?.shutdown() }
    }

    private func applyDatabaseIfNeeded(_ database: String?, on connection: SessionConnection) async throws {
        guard let database, !database.isEmpty else { return }
        if databaseApplied, database == currentDatabase { return }
        try await connection.useDatabase(database)
        currentDatabase = database
        databaseApplied = true
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
        epoch += 1
        databaseApplied = false
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
