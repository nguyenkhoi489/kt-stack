import KTStackKit
import SwiftUI

struct NginxIncludeEditorSheet: View {
    @EnvironmentObject private var server: LocalServerController
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var phase: Phase = .idle

    private let store = NginxUserIncludeStore()

    private enum Phase {
        case idle, saving, validating, reloading, error(String)

        var isBusy: Bool {
            switch self {
            case .saving, .validating, .reloading: return true
            default: return false
            }
        }

        var errorMessage: String? {
            if case .error(let msg) = self { return msg }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Text("Edit nginx config").font(KDFont.title)
            Text("Changes are validated with nginx -t and reloaded. A .bak is kept for revert.")
                .font(KDFont.footnote).foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(KDFont.mono)
                .frame(minWidth: 560, minHeight: 360)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5))
                .disabled(phase.isBusy)

            if let msg = phase.errorMessage {
                ScrollView {
                    Text(msg)
                        .font(KDFont.footnote).foregroundStyle(Color.KDStatus.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }

            HStack {
                Button("Reset to Default", action: reset).disabled(phase.isBusy)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(phase.isBusy)
                Button(saveLabel, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(phase.isBusy || text.isEmpty)
            }
        }
        .padding(KDSpacing.space4)
        .frame(width: 640)
        .onAppear(perform: load)
    }

    private var saveLabel: String {
        switch phase {
        case .saving: return "Saving…"
        case .validating: return "Validating…"
        case .reloading: return "Reloading…"
        default: return "Save"
        }
    }

    private func load() {
        text = (try? store.read()) ?? NginxUserIncludeTemplate.default
        phase = .idle
    }

    private func save() {
        phase = .saving
        let store = store
        let candidate = text
        Task {
            // Step 1: write to disk (creates .bak of previous content)
            do {
                try store.write(contents: candidate)
            } catch {
                phase = .error(error.localizedDescription)
                return
            }

            // Step 2: validate — nginx -t reads the real on-disk include
            phase = .validating
            let result = await server.validateNginxConfig()
            switch result {
            case .valid:
                break // proceed to reload
            case .invalid(let stderr):
                _ = try? store.restoreBackup()
                phase = .error(
                    "nginx rejected the config (not applied):\n\(stderr)\n\n" +
                    "If the path above is not nginx-extra.conf, the problem is in a generated vhost, not your edit."
                )
                return
            case .couldNotRun:
                // Do not revert — the config was not rejected, just unverifiable.
                phase = .error("Could not validate: nginx is not runnable. The file was written but could not be confirmed safe.")
                return
            }

            // Step 3: reload
            phase = .reloading
            do {
                try await server.reloadNginxConfig()
            } catch {
                _ = try? store.restoreBackup()
                phase = .error(
                    "Config valid but reload failed; reverted to the previous nginx-extra.conf.\n\(error.localizedDescription)"
                )
                return
            }

            dismiss()
        }
    }

    private func reset() {
        _ = try? store.resetToDefault()
        text = NginxUserIncludeTemplate.default
        phase = .idle
    }
}
