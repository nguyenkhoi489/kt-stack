import Combine
import Foundation
import Network

public final class DumpServer: @unchecked Sendable {
    public static let preferredPort: UInt16 = 9912
    private static let maxEvents = 500

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.ktstack.dumpserver", qos: .utility)
    private let subject = PassthroughSubject<DumpEvent, Never>()

    public var eventsPublisher: AnyPublisher<DumpEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    public private(set) var port: UInt16 = DumpServer.preferredPort

    public init() {}

    @discardableResult
    public func start() throws -> UInt16 {
        stop()
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let assignedPort: NWEndpoint.Port = if let preferred = NWEndpoint.Port(rawValue: Self.preferredPort) {
            preferred
        } else {
            .any
        }

        let l = try NWListener(using: params, on: assignedPort)
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.port = self?.listener?.port?.rawValue ?? Self.preferredPort
            }
            if case .failed = state {
                self?.attemptFallbackPort()
            }
        }
        l.start(queue: queue)
        listener = l
        return port
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func attemptFallbackPort() {
        guard let l = try? NWListener(using: NWParameters.tcp, on: .any) else { return }
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.port = self?.listener?.port?.rawValue ?? Self.preferredPort
            }
        }
        l.start(queue: queue)
        listener = l
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readLines(from: connection, buffer: Data())
    }

    private func readLines(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data = content { accumulated.append(data) }

            while let newline = accumulated.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = accumulated[accumulated.startIndex..<newline]
                if !lineData.isEmpty, let event = try? DumpEventDecoder.decode(line: Data(lineData)) {
                    subject.send(event)
                }
                accumulated = accumulated[accumulated.index(after: newline)...]
            }

            if !isComplete, error == nil {
                readLines(from: connection, buffer: accumulated)
            } else {
                connection.cancel()
            }
        }
    }
}
