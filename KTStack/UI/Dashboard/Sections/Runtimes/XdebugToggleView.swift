import KTStackKit
import SwiftUI

@MainActor
final class XdebugToggleModel: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var supported = false
    @Published private(set) var busy = false
    @Published var error: String?

    let version: String
    private let controller: XdebugController

    init(version: String, reloadPool: @escaping (String) async throws -> Void) {
        self.version = version
        controller = XdebugController(paths: AppSupportPaths(), reloadPool: reloadPool)
        supported = controller.isSupported(version: version)
        enabled = controller.isEnabled(version: version)
    }

    func toggle(_ on: Bool) {
        guard !busy, supported else { return }
        busy = true
        error = nil
        Task {
            do {
                if on { try await controller.enable(version: version) }
                else { try await controller.disable(version: version) }
            } catch {
                self.error = error.localizedDescription
            }
            enabled = controller.isEnabled(version: version)
            busy = false
        }
    }
}

struct XdebugToggleView: View {
    @StateObject private var model: XdebugToggleModel

    init(version: String, reloadPool: @escaping (String) async throws -> Void) {
        _model = StateObject(wrappedValue: XdebugToggleModel(version: version, reloadPool: reloadPool))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space1) {
            Toggle(isOn: Binding(get: { model.enabled }, set: { model.toggle($0) })) {
                HStack {
                    Text("Xdebug").font(KDFont.body)
                    StatusPill(model.enabled ? .running : .stopped, text: model.enabled ? "on" : "off")
                }
            }
            .disabled(!model.supported || model.busy)

            if !model.supported {
                Text("Not available for PHP \(model.version) on this platform.")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
            } else {
                Text("Step debugger on port \(XdebugController.clientPort). Toggling restarts PHP \(model.version) — sites on this version blip briefly.")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(KDFont.footnote).foregroundStyle(Color.KDStatus.error)
            }
        }
    }
}
