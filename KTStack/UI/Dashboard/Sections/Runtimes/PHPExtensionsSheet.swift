import KTStackKit
import SwiftUI

struct PHPExtensionsSheet: View {
    let version: String
    @EnvironmentObject private var server: LocalServerController
    @StateObject private var model: PHPExtensionsModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingUninstall: PHPExtension?

    init(version: String) {
        self.version = version
        _model = StateObject(wrappedValue: PHPExtensionsModel(version: version))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Extensions — PHP \(version)").font(KDFont.title)
                Text("Install or remove optional extensions. Changes restart PHP \(version).")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
            }
            .padding(KDSpacing.space3)
            Divider()

            XdebugToggleView(version: version, reloadPool: reloadPool)
                .padding(KDSpacing.space3)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        PHPExtensionRowView(
                            ext: row.ext, status: row.status,
                            busy: model.busy.contains(row.ext.id),
                            progress: model.progress[row.ext.id],
                            error: model.errors[row.ext.id],
                            onInstall: { Task { await model.install(row.ext.id, reloadPool: reloadPool) } },
                            onUninstall: { pendingUninstall = row.ext }
                        )
                        Divider()
                    }
                }
                .padding(.horizontal, KDSpacing.space3)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(KDSpacing.space3)
        }
        .frame(width: 540, height: 480)
        .task { await model.refresh() }
        .alert(item: $pendingUninstall, content: uninstallAlert)
    }

    private func reloadPool(_ version: String) async throws {
        try await server.restartPHPPool(version: version)
    }

    private func uninstallAlert(_ ext: PHPExtension) -> Alert {
        Alert(
            title: Text("Uninstall \(ext.displayName)?"),
            message: Text("Removing \(ext.displayName) restarts PHP \(version). Sites that use it will error until they no longer rely on it."),
            primaryButton: .destructive(Text("Uninstall")) {
                Task { await model.uninstall(ext.id, reloadPool: reloadPool) }
            },
            secondaryButton: .cancel()
        )
    }
}
