import SwiftUI
import Combine
import Sparkle

/// Thin wrapper around Sparkle's standard updater. Owns one `SPUStandardUpdaterController` (which
/// starts the background appcast checks driven by `SUFeedURL` / `SUPublicEDKey` in Info.plist) and
/// exposes a manual "Check for Updates…" command. EdDSA verification is enforced by Sparkle using the
/// embedded public key; the private key stays offline / in CI.
final class UpdaterController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    /// Mirrors Sparkle's `canCheckForUpdates` so the menu item disables itself while a check runs.
    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() { updaterController.updater.checkForUpdates() }
}
