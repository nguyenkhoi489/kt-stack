import KTStackKit
import SwiftUI

@MainActor
final class ShellIntegrationModel: ObservableObject {
    @Published private(set) var status: ShellPathManager.Status
    @Published private(set) var busy = false
    @Published private(set) var composerWarning = false
    @Published var errorText: String?

    private let manager: ShellPathManager

    init() {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ktstack-resolve")
        manager = ShellPathManager(paths: AppSupportPaths(), helperSource: helper)
        status = manager.status()
    }

    func setEnabled(_ enabled: Bool) {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            do {
                if enabled { try await manager.enable() } else { try manager.disable() }
            } catch {
                errorText = error.localizedDescription
            }
            status = manager.status()
            composerWarning = status.enabled && !manager.composerProvisioned()
            busy = false
        }
    }

    func reapply() {
        setEnabled(true)
    }
}

struct ShellIntegrationView: View {
    @StateObject private var model = ShellIntegrationModel()

    var body: some View {
        Section("Shell PATH") {
            Toggle("Add php, composer, node and wp to your shell PATH", isOn: Binding(
                get: { model.status.enabled },
                set: { model.setEnabled($0) }
            ))
            .disabled(model.busy)
            Text("Opens a managed PATH block in ~/.zshrc (and bash if present). New terminals run the PHP version each project asks for via .php-version or composer.json.")
                .font(KDFont.footnote).foregroundStyle(.secondary)
            if model.busy {
                Label("Applying…", systemImage: "arrow.triangle.2.circlepath").font(KDFont.footnote)
            }
            if !model.status.shellsPatched.isEmpty {
                Label("Patched: \(model.status.shellsPatched.joined(separator: ", "))", systemImage: "checkmark.circle")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
                Button("Re-apply") { model.reapply() }.disabled(model.busy)
            }
            if model.composerWarning {
                Label(
                    "Composer download didn't finish — the composer command won't work yet. Re-apply to retry.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(KDFont.footnote).foregroundStyle(.orange)
            }
            if let errorText = model.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(KDFont.footnote).foregroundStyle(.red)
            }
        }
    }
}
