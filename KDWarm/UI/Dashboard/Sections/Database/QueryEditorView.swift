import SwiftUI
import KDWarmKit

struct QueryEditorView: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    @State private var showingHistory = false

    private var canRun: Bool {
        guard let tab = vm.activeQueryTab else { return false }
        return vm.connection == .connected
            && !tab.isBusy
            && !tab.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VSplitView {
            editor
            results
        }
        .alert("Run this destructive statement?", isPresented: dangerousBinding,
               presenting: vm.pendingDangerousSQL) { _ in
            Button("Run anyway", role: .destructive) { Task { await vm.runActiveQueryTab(confirmed: true) } }
            Button("Cancel", role: .cancel) { vm.cancelDangerousSQL() }
        } message: { sql in
            Text(DestructiveGuard.evaluate(sql).reason
                 ?? "This statement may change or remove many rows.")
        }
        .sheet(isPresented: $showingHistory) {
            QueryHistorySheet { entry in
                vm.updateActiveQuerySQL(entry.sql)
            }
            .environmentObject(vm)
        }
    }

    private var dangerousBinding: Binding<Bool> {
        Binding(get: { vm.pendingDangerousSQL != nil },
                set: { if !$0 { vm.cancelDangerousSQL() } })
    }

    private var editor: some View {
        VStack(spacing: 0) {
            QueryTabBar()
            Divider()
            HStack {
                Text(vm.selectedDatabase.map { "Database: \($0)" } ?? "No database selected")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
                Spacer()
                if vm.activeQueryTab?.isBusy == true { ProgressView().controlSize(.small) }
                Button { showingHistory = true } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                Button { Task { await vm.runActiveQueryTab() } } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canRun)
            }
            .padding(KDSpacing.space2)
            Divider()
            SQLCodeEditor(text: activeSQLBinding,
                          catalog: vm.schemaCatalog,
                          keywords: SQLKeywords.forKind(vm.selectedProfile?.kind ?? .mysql))
                .frame(minHeight: 80)
        }
    }

    private var activeSQLBinding: Binding<String> {
        Binding(get: { vm.activeQueryTab?.sql ?? "" },
                set: { vm.updateActiveQuerySQL($0) })
    }

    @ViewBuilder
    private var results: some View {
        if let error = vm.activeQueryTab?.resultError {
            EmptyStateView(symbol: "exclamationmark.triangle",
                           title: "SQL error", message: error)
        } else if let result = vm.activeQueryTab?.result {
            VStack(spacing: 0) {
                HStack {
                    Text("\(result.rowCount) rows · \(result.columns.count) columns")
                        .font(KDFont.footnote).foregroundStyle(.secondary)
                    Spacer()
                    CSVExportButton(defaultName: vm.selectedDatabase ?? "result", result: result)
                        .controlSize(.small)
                }
                .padding(KDSpacing.space2)
                Divider()
                ResultsGridView(result: result)
            }
        } else {
            EmptyStateView(symbol: "terminal",
                           title: "Run a query",
                           message: "Type SQL above and press ⌘↩ to see results here.")
        }
    }
}
