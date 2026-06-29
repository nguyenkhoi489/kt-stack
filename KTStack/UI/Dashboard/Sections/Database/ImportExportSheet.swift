import AppKit
import KTStackKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportExportSheet: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    @EnvironmentObject private var documentVM: DocumentViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var tab: Tab = .import
    @State private var exportTable: String = wholeDatabase
    @State private var importFile: URL?
    @State private var targetName: String = ""
    @State private var fullDumpMode = false
    @State private var sqliteMode: SQLiteImportMode = .overwrite
    @State private var sqliteNewPath: URL?
    @State private var pendingExists = false
    @State private var isResolvingTarget = false
    @State private var didInitTarget = false
    @State private var confirmingImport = false

    private static let wholeDatabase = "--whole database--"
    enum Tab: String, CaseIterable, Identifiable { case export = "Export", `import` = "Import"; var id: String {
        rawValue
    } }
    enum SQLiteImportMode: Hashable { case overwrite, newFile }

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
            initializeTarget()
        }
        .alert(confirmTitle, isPresented: $confirmingImport) {
            Button(confirmButtonTitle, role: confirmIsDestructive ? .destructive : nil) { runImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
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
        if tab == .export, !canExport {
            unavailable("Export not supported yet", "Export is currently available only for MySQL connections.")
        } else if tab == .import, !canImport {
            unavailable("Import unavailable", importUnavailableReason)
        } else {
            body(for: tab)
        }
    }

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
            if activeKind == .mysql {
                Toggle("Import entire dump (all databases)", isOn: $fullDumpMode)
                    .toggleStyle(.checkbox)
            }
            if !isFullDump { targetControls }
            HStack(spacing: KDSpacing.space2) {
                Button("Import") { startImport() }
                    .disabled(importFile == nil || !canSubmit || isWorking || isResolvingTarget)
                if isResolvingTarget { ProgressView().controlSize(.small) }
            }
        }
    }

    @ViewBuilder
    private var targetControls: some View {
        if activeKind == .sqlite {
            sqliteTargetControls
        } else {
            VStack(alignment: .leading, spacing: KDSpacing.space1) {
                TextField("Database name", text: $targetName)
                    .textFieldStyle(.roundedBorder)
                Label(nameTargetHint, systemImage: nameTargetIcon)
                    .font(KDFont.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var sqliteTargetControls: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space1) {
            Picker("Destination", selection: $sqliteMode) {
                Text("Replace current file").tag(SQLiteImportMode.overwrite)
                Text("Save as new file…").tag(SQLiteImportMode.newFile)
            }
            .pickerStyle(.radioGroup)
            if sqliteMode == .overwrite {
                Label(sqliteOverwriteText, systemImage: "externaldrive")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
            } else {
                Button("Choose destination…") { chooseSQLiteDestination() }
                if let sqliteNewPath {
                    Text(sqliteNewPath.lastPathComponent).font(KDFont.mono).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if isDocumentTrack {
            switch documentVM.backupStatus {
            case .idle: EmptyView()
            case let .running(message): progressRow(message)
            case let .done(message): successRow(message)
            case let .failed(message): failureRow(message)
            }
        } else {
            switch vm.dumpStatus {
            case .idle: EmptyView()
            case .running: progressRow("Working...")
            case let .done(message): successRow(message)
            case let .failed(message): failureRow(message)
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

    private func initializeTarget() {
        guard !didInitTarget else { return }
        didInitTarget = true
        switch activeKind {
        case .some(.mysql), .some(.sqlite): targetName = vm.selectedDatabase ?? ""
        case .some(.postgres): targetName = vm.selectedProfile?.database ?? ""
        case .some(.mongodb): targetName = documentVM.selectedDatabase ?? ""
        case .none: break
        }
        if activeKind == .sqlite { sqliteMode = hasSQLiteFile ? .overwrite : .newFile }
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

    private func chooseSQLiteDestination() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
        panel.nameFieldStringValue = importFile.map { "\($0.deletingPathExtension().lastPathComponent)-import.sqlite" } ?? "imported.sqlite"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sqliteNewPath = url
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
        if isFullDump {
            pendingExists = false
            confirmingImport = true
            return
        }
        Task {
            isResolvingTarget = true
            pendingExists = await resolveTargetExists()
            isResolvingTarget = false
            confirmingImport = true
        }
    }

    private func resolveTargetExists() async -> Bool {
        switch activeKind {
        case .some(.sqlite): sqliteMode == .overwrite
        case .some(.mongodb): await documentVM.targetDatabaseExists(targetName)
        default: await vm.targetDatabaseExists(targetName)
        }
    }

    private func runImport() {
        guard let file = importFile else { return }
        if isFullDump {
            Task { await vm.importFullDump(from: file) }
            return
        }
        let name = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch activeKind {
        case .some(.sqlite):
            if sqliteMode == .overwrite {
                Task { await vm.importSQLite(from: file, into: .overwrite) }
            } else if let dest = sqliteNewPath {
                Task { await vm.importSQLite(from: file, into: .newDatabase(dest.path)) }
            }
        case .some(.mongodb):
            Task { await documentVM.importDatabase(into: name, from: file, replaceExisting: pendingExists) }
        default:
            Task { await vm.importDatabase(into: name, from: file, replaceExisting: pendingExists) }
        }
    }

    private var isDocumentTrack: Bool {
        documentVM.selectedProfile?.kind == .mongodb
    }

    private var activeKind: DatabaseKind? {
        isDocumentTrack ? documentVM.selectedProfile?.kind : vm.selectedProfile?.kind
    }

    private var canExport: Bool {
        !isDocumentTrack && vm.canDump
    }

    private var canImport: Bool {
        isDocumentTrack ? documentVM.canManualImport : vm.canManualImport
    }

    private var isReadOnly: Bool {
        isDocumentTrack ? documentVM.isReadOnlyConnection : vm.isReadOnlyConnection
    }

    private var isWorking: Bool {
        if isDocumentTrack, case .running = documentVM.backupStatus { return true }
        if !isDocumentTrack, case .running = vm.dumpStatus { return true }
        return false
    }

    private var importUnavailableReason: String {
        (isDocumentTrack ? documentVM.importUnavailableReason : vm.importUnavailableReason)
            ?? "The required database tools aren't available."
    }

    private var hasSQLiteFile: Bool {
        guard let path = vm.selectedProfile?.filePath else { return false }
        return !path.isEmpty
    }

    private var isFullDump: Bool {
        activeKind == .mysql && fullDumpMode
    }

    private var canSubmit: Bool {
        if isFullDump { return true }
        switch activeKind {
        case .some(.sqlite):
            return sqliteMode == .overwrite ? hasSQLiteFile : sqliteNewPath != nil
        default:
            return !targetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var liveTargetExists: Bool? {
        let name = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        switch activeKind {
        case .some(.mysql): return vm.databases.contains { $0.name == name }
        case .some(.mongodb): return documentVM.databases.contains { $0.name == name }
        default: return nil
        }
    }

    private var nameTargetHint: String {
        let name = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Type the target database name." }
        switch liveTargetExists {
        case .some(true): return "Will overwrite existing database \"\(name)\"."
        case .some(false): return "Will create new database \"\(name)\"."
        case .none: return "Creates \"\(name)\" if missing, otherwise overwrites it."
        }
    }

    private var nameTargetIcon: String {
        switch liveTargetExists {
        case .some(true): "exclamationmark.triangle"
        case .some(false): "plus.circle"
        case .none: "cylinder"
        }
    }

    private var importButtonTitle: String {
        switch activeKind {
        case .some(.mysql): "Choose MySQL .sql file..."
        case .some(.postgres): "Choose PostgreSQL .sql/.dump file..."
        case .some(.sqlite): "Choose SQLite .sqlite/.db file..."
        case .some(.mongodb): "Choose MongoDB dump folder..."
        case .none: "Choose import file..."
        }
    }

    private var importExtensions: [String] {
        switch activeKind {
        case .some(.mysql): ["sql"]
        case .some(.postgres): ["sql", "dump"]
        case .some(.sqlite): ["sqlite", "db"]
        case .some(.mongodb), .none: []
        }
    }

    private var sqliteOverwriteText: String {
        guard let path = vm.selectedProfile?.filePath, !path.isEmpty else {
            return "No SQLite file selected for this connection; save as a new file instead."
        }
        return "Replaces \(URL(fileURLWithPath: path).lastPathComponent)."
    }

    private var confirmIsDestructive: Bool {
        if isFullDump { return true }
        if activeKind == .sqlite { return sqliteMode == .overwrite }
        return pendingExists
    }

    private var confirmButtonTitle: String {
        if isFullDump { return "Import all" }
        if activeKind == .sqlite { return sqliteMode == .overwrite ? "Replace" : "Save" }
        return pendingExists ? "Overwrite" : "Create & Import"
    }

    private var confirmTitle: String {
        if isFullDump { return "Import all databases?" }
        if activeKind == .sqlite {
            return sqliteMode == .overwrite ? "Replace SQLite database?" : "Save to new file?"
        }
        return pendingExists ? "Overwrite database?" : "Create new database?"
    }

    private var confirmMessage: String {
        if isFullDump {
            return "Every database in the dump will be created or overwritten by its CREATE DATABASE/USE statements. This can't be undone."
        }
        let name = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        if activeKind == .sqlite {
            return sqliteMode == .overwrite
                ? "The selected SQLite file will replace the active database file. This can't be undone."
                : "A new SQLite file will be created from the imported snapshot."
        }
        return pendingExists
            ? "Loading into \"\(name)\" can overwrite existing data. This can't be undone."
            : "A new database \"\(name)\" will be created and the file imported."
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
