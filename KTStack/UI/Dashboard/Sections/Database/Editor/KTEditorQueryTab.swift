import SwiftUI
import KTStackKit

struct KTEditorQueryTab: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    let isActive: Bool

    private var canRun: Bool {
        guard let tab = vm.activeQueryTab else { return false }
        return vm.connection == .connected
            && !tab.isBusy
            && !tab.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isBusy: Bool { vm.activeQueryTab?.isBusy ?? false }

    private var sqlBinding: Binding<String> {
        Binding(get: { vm.activeQueryTab?.sql ?? "" }, set: { vm.updateActiveQuerySQL($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            editorPanel
            results
        }
        .task(id: EditorTabTaskKey(value: vm.selectedDatabase, isActive: isActive)) {
            guard isActive else { return }
            await vm.ensureSchemaCatalogLoaded()
        }
        .alert("Run this destructive statement?", isPresented: dangerousBinding,
               presenting: vm.pendingDangerousSQL) { _ in
            Button("Run anyway", role: .destructive) { Task { await vm.runActiveQueryTab(confirmed: true) } }
            Button("Cancel", role: .cancel) { vm.cancelDangerousSQL() }
        } message: { sql in
            Text(destructiveMessage(for: sql))
        }
    }

    private func destructiveMessage(for sql: String) -> String {
        var message = DestructiveGuard.evaluate(sql).reason ?? "This statement may change or remove many rows."
        if vm.activeQueryTab?.result?.truncated == true {
            message += "\n\nThe last result was truncated to \(SQLAutoLimit.defaultMax) rows, so it may not reflect every row this statement affects."
        }
        return message
    }

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SQLCodeEditor(text: sqlBinding,
                          catalog: vm.schemaCatalog,
                          keywords: SQLKeywords.forKind(vm.selectedProfile?.kind ?? .mysql))
                .frame(minHeight: 96, maxHeight: 160)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(KTColor.fieldBorder, lineWidth: 0.5))
            HStack(spacing: 10) {
                runButton
                if isBusy { stopButton }
                Button("Format") { sqlBinding.wrappedValue = KTSQLFormatter.format(sqlBinding.wrappedValue) }
                    .buttonStyle(SecondaryQueryButton())
                Spacer()
                if let result = vm.activeQueryTab?.result {
                    Text("\(result.rowCount) rows · \(result.columns.count) cols")
                        .font(.jbMono(12.5)).foregroundStyle(KTColor.muted)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sep).frame(height: 0.5) }
    }

    private var runButton: some View {
        Button { Task { await vm.runActiveQueryTab() } } label: {
            HStack(spacing: 7) {
                Image(systemName: "play.fill").font(.system(size: 11))
                Text("Run Query").font(.jbMono(13, .regular))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KTColor.accentGradient))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!canRun)
        .opacity(canRun ? 1 : 0.5)
    }

    private var stopButton: some View {
        Button { Task { await vm.cancelRunningQuery() } } label: {
            HStack(spacing: 7) {
                Image(systemName: "stop.fill").font(.system(size: 11))
                Text("Stop").font(.jbMono(13, .regular))
            }
            .foregroundStyle(KTColor.ink2)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(KTColor.btnBorder, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(".", modifiers: .command)
    }

    @ViewBuilder
    private var results: some View {
        if let error = vm.activeQueryTab?.resultError {
            messageState(icon: "exclamationmark.triangle", title: "SQL error", message: error)
        } else if let notice = vm.activeQueryTab?.resultNotice {
            messageState(icon: "stop.circle", title: "Query cancelled", message: notice)
        } else if let result = vm.activeQueryTab?.result {
            VStack(spacing: 0) {
                if result.truncated { truncationBanner }
                KTDataGrid(result: result)
            }
        } else {
            messageState(icon: "terminal", title: "Run a query", message: "Type SQL above and press ⌘↩ to see results here.")
        }
    }

    private var truncationBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
                .foregroundStyle(KTIconTint.db.fg)
            Text("Showing the first \(SQLAutoLimit.defaultMax) rows — result truncated (LIMIT applied). Add your own LIMIT or refine the query to see more.")
                .font(.jbMono(12.5)).foregroundStyle(KTColor.ink2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KTIconTint.db.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sep).frame(height: 0.5) }
    }

    private func messageState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 42, weight: .light)).foregroundStyle(KTColor.faint)
            Text(title).font(.jbMono(16, .regular)).foregroundStyle(KTColor.ink3)
            Text(message).font(.jbMono(13)).foregroundStyle(KTColor.muted).multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dangerousBinding: Binding<Bool> {
        Binding(get: { vm.pendingDangerousSQL != nil }, set: { if !$0 { vm.cancelDangerousSQL() } })
    }
}

private struct SecondaryQueryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.jbMono(13, .medium))
            .foregroundStyle(KTColor.ink2)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(KTColor.btnBorder, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
