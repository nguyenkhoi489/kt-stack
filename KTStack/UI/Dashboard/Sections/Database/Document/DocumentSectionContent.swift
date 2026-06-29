import KTStackKit
import SwiftUI

struct DocumentSectionContent: View {
    @EnvironmentObject private var vm: DocumentViewModel
    @EnvironmentObject private var services: ServiceManager

    var body: some View {
        switch vm.connection {
        case .connected:
            HSplitView {
                CollectionTreeView()
                DocumentListView().frame(minWidth: 360)
            }
        case .connecting:
            ProgressView("Connecting…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            failureGate(error)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func failureGate(_ error: DatabaseError) -> some View {
        switch error {
        case .engineNotInstalled:
            EmptyStateView(
                symbol: "shippingbox",
                title: "MongoDB isn’t installed",
                message: "Install the managed MongoDB engine, then reconnect.",
                actionTitle: "Install MongoDB…",
                action: { services.install(.mongodb) }
            )
        case .engineNotRunning:
            EmptyStateView(
                symbol: "play.circle",
                title: "MongoDB isn’t running",
                message: "Start the MongoDB engine, then reconnect.",
                actionTitle: "Start MongoDB",
                action: { services.toggle(.mongodb) }
            )
        default:
            EmptyStateView(
                symbol: "exclamationmark.triangle",
                title: "Connection failed",
                message: error.message,
                actionTitle: "Retry",
                action: retry
            )
        }
    }

    private func retry() {
        guard let profile = vm.selectedProfile else { return }
        Task { await vm.select(profile: profile) }
    }
}
