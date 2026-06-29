import KTStackKit
import SwiftUI

struct PHPIniEditorSheet: View {
    let version: String
    @EnvironmentObject private var server: LocalServerController
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var error: String?
    @State private var isSaving = false

    private let store = PHPIniStore()

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Text("Edit php.ini — PHP \(version)").font(KDFont.title)
            Text("Saved changes reload PHP \(version) only. A .bak is kept for revert.")
                .font(KDFont.footnote).foregroundStyle(.secondary)

            TextEditor(text: $text)
                .font(KDFont.mono)
                .frame(minWidth: 560, minHeight: 360)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5))
                .disabled(isSaving)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(KDFont.footnote).foregroundStyle(Color.KDStatus.error)
                    .lineLimit(3)
            }

            HStack {
                Button("Reset to Default", action: reset).disabled(isSaving)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isSaving)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || text.isEmpty)
            }
        }
        .padding(KDSpacing.space4)
        .frame(width: 640)
        .onAppear(perform: load)
    }

    private func load() {
        do { text = try store.read(version: version); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func save() {
        error = nil
        isSaving = true
        let candidate = text
        let store = store
        let version = version
        Task {
            if let problem = await Task.detached(priority: .userInitiated, operation: {
                store.validate(version: version, contents: candidate)
            }).value {
                error = "php.ini has a syntax error (not applied):\n\(problem)"
                isSaving = false
                return
            }
            do {
                try store.write(version: version, contents: candidate) // atomic + .bak
            } catch {
                self.error = error.localizedDescription
                isSaving = false
                return
            }
            do {
                try await server.reloadPHPPool(version: version)
                isSaving = false
                dismiss()
            } catch {
                _ = try? store.restoreBackup(version: version)
                try? await server.reloadPHPPool(version: version)
                self.error = "Reload failed; reverted to the previous php.ini.\n\(error.localizedDescription)"
                isSaving = false
            }
        }
    }

    private func reset() {
        text = PHPIniTemplate.default
        error = nil
    }
}
