import SwiftUI
import KDWarmKit
import AppKit
import UniformTypeIdentifiers

struct ImportExportSheet: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    @EnvironmentObject private var documentVM: DocumentViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var tab: Tab = .import
    @State private var exportTable: String = wholeDatabase
    @State private var importFile: URL?
    @State private var confirmingImport = false

    private static let wholeDatabase = "--whole database--"
    enum Tab: String, CaseIterable, Identifiable { case export = "Export", `import` = "Import"; var id: String { rawValue } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 480, height: 380)
        .onAppear {
            if !canExport { tab = .import }
            vm.clearDumpStatus()
            documentVM.clearBackupStatus()
        }
        .alert(importConfirmationTitle, isPresented: $confirmingImport) {
            Button("Import", role: .destructive) { runImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(importConfirmationMessage)
        }
    }

    private var header: some View {
        VStack(spacing: KDSpacing.space2) {
            Text(canExport ? "Database Import / Export" : "Database Import").font(KDFont.title)
            if canExport {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
        }
        .padding(KDSpacing.space3)
    }

    @ViewBuilder
    private var content: some View {
        if tab == .export && !canExport {
            unavailable("Export not supported yet", "Export is currently available only for MySQL connections.")
        } else if tab == .import && !canImport {
            unavailable("Import unavailable", importUnavailableReason)
        } else {
            body(for: tab)
        }
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

    private var exportForm: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space2) {
            Text("Database: \(vm.selectedDatabase ?? "none")").font(KDFont.body)
            Picker("Scope", selection: $exportTable) {
                Text("Whole database").tag(Self.wholeDatabase)
                ForEach(vm.tables) { Text($0.name).tag($0.name) }
            }
            Button("Export to .sql...") { chooseExportDestination() }
                .disabled(vm.selectedDatabase == nil || isWorking)
        }
    }

    @ViewBuilder
    private var importForm: some View {
        if isReadOnly {
            Label("This connection is read-only; importing is disabled.", systemImage: "lock")
                .font(KDFont.footnote).foregroundStyle(.secondary)
        } else {
            importControls
        }
    }

    private var importControls: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space2) {
            Button(importButtonTitle) { chooseImportFile() }
            if let importFile {
                Text(importFile.lastPathComponent).font(KDFont.mono).foregroundStyle(.secondary)
            }
            targetControls
            Button("Import") { startImport() }
                .disabled(importFile == nil || importTarget == nil || isWorking)
        }
    }

    @ViewBuilder
    private var targetControls: some View {
        if let targetLabel = importTargetLabel {
            Label(targetLabel, systemImage: activeKind == .sqlite ? "externaldrive" : "cylinder")
                .font(KDFont.footnote).foregroundStyle(.secondary)
        } else {
            Label("Pick a database before importing.", systemImage: "exclamationmark.triangle")
                .font(KDFont.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if isDocumentTrack {
            switch documentVM.backupStatus {
            case .idle: EmptyView()
            case .running(let message): progressRow(message)
            case .done(let message): successRow(message)
            case .failed(let message): failureRow(message)
            }
        } else {
            switch vm.dumpStatus {
            case .idle: EmptyView()
            case .running: progressRow("Working...")
            case .done(let message): successRow(message)
            case .failed(let message): failureRow(message)
            }
        }
    }

    private var footer: some View {
        HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            .padding(KDSpacing.space3)
    }

    private func unavailable(_ title: String, _ message: String) -> some View {
        EmptyStateView(symbol: "shippingbox", title: title, message: message)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
        configureImportPanel(panel)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile = url
    }

    private func configureImportPanel(_ panel: NSOpenPanel) {
        panel.allowsMultipleSelection = false
        if activeKind == .mongodb {
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            return
        }
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let contentTypes = importExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = contentTypes.isEmpty ? [.data] : contentTypes
    }

    private func startImport() {
        confirmingImport = true
    }

    private func runImport() {
        guard let file = importFile, let target = importTarget else { return }
        if isDocumentTrack {
            Task { await documentVM.importDatabase(into: target, from: file, replaceExisting: true) }
        } else {
            Task { await vm.importDatabase(into: target, from: file, replaceExisting: true) }
        }
    }

    private var isDocumentTrack: Bool { documentVM.selectedProfile?.kind == .mongodb }
    private var activeKind: DatabaseKind? { isDocumentTrack ? documentVM.selectedProfile?.kind : vm.selectedProfile?.kind }
    private var canExport: Bool { !isDocumentTrack && vm.canDump }
    private var canImport: Bool { isDocumentTrack ? documentVM.canManualImport : vm.canManualImport }
    private var isReadOnly: Bool { isDocumentTrack ? documentVM.isReadOnlyConnection : vm.isReadOnlyConnection }
    private var isWorking: Bool {
        if isDocumentTrack, case .running = documentVM.backupStatus { return true }
        if !isDocumentTrack, case .running = vm.dumpStatus { return true }
        return false
    }
    private var importUnavailableReason: String {
        (isDocumentTrack ? documentVM.manualImportUnavailableReason : vm.manualImportUnavailableReason)
            ?? "The required database tools aren't available."
    }
    private var importTarget: String? {
        switch activeKind {
        case .some(.mysql):
            return vm.selectedDatabase
        case .some(.postgres):
            let database = vm.selectedProfile?.database.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return database.isEmpty ? nil : database
        case .some(.sqlite):
            return vm.selectedDatabase ?? "main"
        case .some(.mongodb):
            return documentVM.selectedDatabase
        case .none:
            return nil
        }
    }
    private var importTargetLabel: String? {
        switch activeKind {
        case .some(.mysql), .some(.mongodb):
            guard let importTarget else { return nil }
            return "Imports into \(importTarget)."
        case .some(.postgres):
            guard let importTarget else { return nil }
            return "Imports into PostgreSQL database \(importTarget)."
        case .some(.sqlite):
            return sqliteTargetText
        case .none:
            return nil
        }
    }
    private var importButtonTitle: String {
        switch activeKind {
        case .some(.mysql): return "Choose MySQL .sql file..."
        case .some(.postgres): return "Choose PostgreSQL .sql/.dump file..."
        case .some(.sqlite): return "Choose SQLite .sqlite/.db file..."
        case .some(.mongodb): return "Choose MongoDB dump folder..."
        case .none: return "Choose import file..."
        }
    }
    private var importExtensions: [String] {
        switch activeKind {
        case .some(.mysql): return ["sql"]
        case .some(.postgres): return ["sql", "dump"]
        case .some(.sqlite): return ["sqlite", "db"]
        case .some(.mongodb), .none: return []
        }
    }
    private var sqliteTargetText: String {
        guard let path = vm.selectedProfile?.filePath, !path.isEmpty else {
            return "Import replaces the selected SQLite database file."
        }
        return "Import replaces \(URL(fileURLWithPath: path).lastPathComponent)."
    }
    private var importConfirmationTitle: String {
        activeKind == .sqlite ? "Replace SQLite database?" : "Import into selected database?"
    }
    private var importConfirmationMessage: String {
        if activeKind == .sqlite {
            return "The selected SQLite file will replace the active database file. This can't be undone."
        }
        return "Loading into \"\(importTarget ?? "the selected database")\" can overwrite existing data. This can't be undone."
    }
    private var scopeName: String {
        exportTable == Self.wholeDatabase ? (vm.selectedDatabase ?? "export") : exportTable
    }

    private func progressRow(_ message: String) -> some View {
        HStack(spacing: KDSpacing.space2) { ProgressView().controlSize(.small); Text(message).font(KDFont.footnote) }
    }

    private func successRow(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle.fill").font(KDFont.footnote).foregroundStyle(.green)
    }

    private func failureRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill").font(KDFont.footnote).foregroundStyle(.orange)
    }
}
