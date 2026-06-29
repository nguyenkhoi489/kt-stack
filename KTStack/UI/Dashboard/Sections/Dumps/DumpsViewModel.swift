import Combine
import KTStackKit
import SwiftUI

@MainActor
final class DumpsViewModel: ObservableObject {
    @Published private(set) var events: [DumpEvent] = []
    @Published var enabled = false
    @Published var autoScroll = true
    @Published var errorMessage: String?
    @Published private(set) var busy = false

    private let dumpServer = DumpServer()
    private let injector = DumpInjector()
    private var server: LocalServerController?
    private var cancellable: AnyCancellable?
    private static let eventCap = 300

    init() {
        cancellable = dumpServer.eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                events.append(event)
                if events.count > Self.eventCap {
                    events.removeFirst(events.count - Self.eventCap)
                }
            }
    }

    func configure(server: LocalServerController) {
        self.server = server
    }

    func toggle(_ on: Bool) {
        guard let server, !busy else { return }
        busy = true
        errorMessage = nil
        Task {
            do {
                if on {
                    let port = try dumpServer.start()
                    for version in server.availableVersions {
                        try injector.enable(version: version, port: port)
                        try await server.reloadPHPPool(version: version)
                    }
                } else {
                    for version in server.availableVersions {
                        try injector.disable(version: version)
                        try await server.reloadPHPPool(version: version)
                    }
                    dumpServer.stop()
                }
                enabled = on
            } catch {
                errorMessage = error.localizedDescription
                if on { dumpServer.stop() }
            }
            busy = false
        }
    }

    func clear() {
        events = []
    }

    func shutdownForQuit() {
        guard let server else {
            dumpServer.stop()
            return
        }
        let versions = server.availableVersions
        Task { @MainActor in
            for version in versions {
                try? injector.disable(version: version)
                try? await server.reloadPHPPool(version: version)
            }
            injector.cleanupPrependFile()
            dumpServer.stop()
        }
    }
}
