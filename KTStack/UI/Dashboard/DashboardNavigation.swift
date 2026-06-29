import KTStackKit
import SwiftUI

@MainActor
final class DashboardNavigation: ObservableObject {
    @Published var selection: SidebarItem = .sites
    @Published var activeItem: SidebarItem?
    @Published var logTarget: String?

    func openLogs(_ sourceID: String?) {
        logTarget = sourceID
        selection = .logs
    }
}
