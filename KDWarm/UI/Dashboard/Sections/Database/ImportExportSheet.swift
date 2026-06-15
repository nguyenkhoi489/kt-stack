import SwiftUI
import KDWarmKit
import AppKit

/// Export a database/table to `.sql` and import a dump back. Import defaults to a NEW database
/// (a killed load can't corrupt unrelated data); loading into an existing database is a separate,
/// explicitly-confirmed "replace" path. Disabled with guidance when the dump tools aren't installed.
struct ImportExportSheet: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var tab: Tab = .export
    @State private var exportTable: String = wholeDatabase
    @State private var importFile: URL?
    @State private var targetDB = ""
    @State private var replaceExisting = false
    @State private var confirmingReplace = false

    private static let wholeDatabase = "—whole database—"
    enum Tab: String, CaseIterable, Identifiable { case export = "Export", `import` = "Import"; var id: String { rawValue } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if vm.canDump { body(for: tab) } else { engineMissing }
            Divider()
            footer
        }
        .frame(width: 460, height: 360)
        .alert("Replace existing database?", isPresented: $confirmingReplace) {
            Button("Replace", role: .destructive) { runImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Loading into “\(targetDB)” merges the dump into existing data and can overwrite rows. This can't be undone.")
        }
    }

    private var header: some View {
        VStack(spacing: KDSpacing.space2) {
            Text("Import / Export").font(KDFont.title)
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
        }
        .padding(KDSpacing.space3)
    }

    @ViewBuilder
    private func body(for tab: Tab) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KDSpacing.space3) {
                switch tab {
                case .export: exportForm
                case .import: importForm
                }
                statusRow
            }
            .padding(KDSpacing.space3)
        }
    }

    // MARK: - Export

    private var exportForm: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space2) {
            Text("Database: \(vm.selectedDatabase ?? "none")").font(KDFont.body)
            Picker("Scope", selection: $exportTable) {
                Text("Whole database").tag(Self.wholeDatabase)
                ForEach(vm.tables) { Text($0.name).tag($0.name) }
            }
            Button("Export to .sql…") { chooseExportDestination() }
                .disabled(vm.selectedDatabase == nil || vm.dumpStatus == .running)
        }
    }

    // MARK: - Import

    @ViewBuilder
    private var importForm: some View {
        if vm.isReadOnlyConnection {
            Label("This connection is read-only; importing is disabled.", systemImage: "lock")
                .font(KDFont.footnote).foregroundStyle(.secondary)
        } else {
            importControls
        }
    }

    private var importControls: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space2) {
            Button("Choose .sql file…") { chooseImportFile() }
            if let importFile { Text(importFile.lastPathComponent).font(KDFont.mono).foregroundStyle(.secondary) }
            Toggle("Load into an existing database (replace)", isOn: $replaceExisting)
                .toggleStyle(.checkbox).font(KDFont.footnote)
            if replaceExisting {
                Picker("Target", selection: $targetDB) {
                    Text("Select…").tag("")
                    ForEach(vm.databases) { Text($0.name).tag($0.name) }
                }
            } else {
                TextField("New database name", text: $targetDB)
                    .textFieldStyle(.roundedBorder).font(KDFont.mono)
            }
            Button("Import") { startImport() }
                .disabled(importFile == nil || targetDB.isEmpty || vm.dumpStatus == .running)
        }
    }

    // MARK: - Status / footer

    @ViewBuilder
    private var statusRow: some View {
        switch vm.dumpStatus {
        case .idle: EmptyView()
        case .running:
            HStack(spacing: KDSpacing.space2) { ProgressView().controlSize(.small); Text("Working…").font(KDFont.footnote) }
        case .done(let message):
            Label(message, systemImage: "checkmark.circle.fill").font(KDFont.footnote).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(KDFont.footnote).foregroundStyle(.orange)
        }
    }

    private var engineMissing: some View {
        let isMySQL = vm.selectedProfile?.kind == .mysql
        return EmptyStateView(
            symbol: "shippingbox",
            title: isMySQL ? "Dump tools unavailable" : "Import/Export not supported yet",
            message: isMySQL
                ? "Install the MySQL engine to enable dump tools."
                : "Import/Export is currently available only for MySQL connections.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            .padding(KDSpacing.space3)
    }

    // MARK: - Actions

    private func chooseExportDestination() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "sql") ?? .data]
        panel.nameFieldStringValue = "\(scopeName).sql"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let table = exportTable == Self.wholeDatabase ? nil : exportTable
        Task { await vm.exportDatabase(to: url, table: table) }
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "sql") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile = url
        if targetDB.isEmpty && !replaceExisting {
            targetDB = url.deletingPathExtension().lastPathComponent
        }
    }

    private func startImport() {
        if replaceExisting { confirmingReplace = true } else { runImport() }
    }

    private func runImport() {
        guard let file = importFile else { return }
        Task { await vm.importDatabase(into: targetDB, from: file) }
    }

    private var scopeName: String {
        exportTable == Self.wholeDatabase ? (vm.selectedDatabase ?? "export") : exportTable
    }
}
