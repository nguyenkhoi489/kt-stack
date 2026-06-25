import XCTest
@testable import KTStackKit

final class ConnectionSessionTests: XCTestCase {

    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var opens = 0
        private(set) var maxConcurrent = 0
        private var current = 0

        func opened() { lock.lock(); opens += 1; lock.unlock() }
        func enter() {
            lock.lock(); current += 1; maxConcurrent = max(maxConcurrent, current); lock.unlock()
        }
        func leave() { lock.lock(); current -= 1; lock.unlock() }
    }

    private final class FakeConnection: SessionConnection, @unchecked Sendable {
        let probe: Probe
        var live = true

        init(probe: Probe) {
            self.probe = probe
            probe.opened()
        }

        var isLive: Bool { live }

        func useDatabase(_ database: String) async throws {}

        func runText(_ sql: String) async throws -> QueryResult {
            probe.enter()
            defer { probe.leave() }
            try? await Task.sleep(for: .milliseconds(25))
            return QueryResult(columns: [ColumnMeta(name: sql)], rows: [])
        }

        func runSelect(_ statement: DMLStatement) async throws -> QueryResult {
            probe.enter()
            defer { probe.leave() }
            try? await Task.sleep(for: .milliseconds(25))
            return QueryResult(columns: [ColumnMeta(name: statement.sql)], rows: [statement.binds])
        }

        func shutdown() async { live = false }
    }

    private final class ConnectionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var connections: [FakeConnection] = []
        func add(_ connection: FakeConnection) { lock.lock(); connections.append(connection); lock.unlock() }
        var last: FakeConnection? { lock.lock(); defer { lock.unlock() }; return connections.last }
    }

    private func makeSession(probe: Probe, box: ConnectionBox) -> ConnectionSession {
        ConnectionSession {
            let connection = FakeConnection(probe: probe)
            box.add(connection)
            return connection
        }
    }

    func testReusesASingleConnectionAcrossCommands() async throws {
        let probe = Probe()
        let session = makeSession(probe: probe, box: ConnectionBox())
        _ = try await session.runText("a")
        _ = try await session.runText("b")
        _ = try await session.runSelect(DMLStatement(sql: "c", binds: []))
        XCTAssertEqual(probe.opens, 1)
    }

    func testSerializesOverlappingCommands() async throws {
        let probe = Probe()
        let session = makeSession(probe: probe, box: ConnectionBox())
        async let first = session.runText("a")
        async let second = session.runText("b")
        async let third = session.runText("c")
        _ = try await (first, second, third)
        XCTAssertEqual(probe.maxConcurrent, 1)
    }

    func testReconnectsAfterTheConnectionDies() async throws {
        let probe = Probe()
        let box = ConnectionBox()
        let session = makeSession(probe: probe, box: box)
        _ = try await session.runText("a")
        XCTAssertEqual(probe.opens, 1)

        box.last?.live = false
        _ = try await session.runText("b")
        XCTAssertEqual(probe.opens, 2)
    }

    func testRunSelectCarriesBindsThroughUnchanged() async throws {
        let probe = Probe()
        let session = makeSession(probe: probe, box: ConnectionBox())
        let binds: [Cell] = [.text("o'brien"), .int(7), .null]
        let result = try await session.runSelect(DMLStatement(sql: "SELECT", binds: binds))
        XCTAssertEqual(result.rows.first, binds)
    }

    func testShutdownClosesTheLiveConnection() async throws {
        let probe = Probe()
        let box = ConnectionBox()
        let session = makeSession(probe: probe, box: box)
        _ = try await session.runText("a")
        await session.shutdown()
        XCTAssertEqual(box.last?.live, false)
    }
}
