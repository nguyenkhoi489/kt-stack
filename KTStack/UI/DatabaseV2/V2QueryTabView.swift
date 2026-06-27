import SwiftUI
import KTStackKit

struct V2QueryTabView: View {
    @ObservedObject var vm: DatabaseV2ViewModel

    var body: some View {
        VStack(spacing: 0) {
            queryTabsBar
            toolbar
            sqlEditor
            Divider().overlay(KTEditorTheme.separator)
            resultsArea
            statusBar
        }
    }

    private var queryTabsBar: some View {
        HStack(spacing: 0) {
            ForEach(vm.queryTabs) { tab in
                tabButton(tab)
            }
            addButton
            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .background(KTEditorTheme.content2)
        .overlay(alignment: .bottom) {
            Divider().overlay(KTEditorTheme.separator)
        }
    }

    private func tabButton(_ tab: V2QueryTab) -> some View {
        let active = tab.id == vm.activeQueryTabID
        return HStack(spacing: 8) {
            if tab.isRunning {
                ProgressView().controlSize(.mini).scaleEffect(0.65).frame(width: 12, height: 12)
            }
            Text(tab.title)
                .font(.system(size: 12))
                .foregroundStyle(active ? KTEditorTheme.label : KTEditorTheme.label2)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if vm.queryTabs.count > 1 {
                Button {
                    vm.closeQueryTab(id: tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(KTEditorTheme.label3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(active ? KTEditorTheme.content : Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle().fill(KTEditorTheme.separator).frame(width: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { vm.selectQueryTab(id: tab.id) }
    }

    private var addButton: some View {
        Button { vm.addQueryTab() } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(KTEditorTheme.label2)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if vm.isRunning {
                V2Button(title: "Cancel", systemImage: "stop.fill", kind: .danger) {
                    Task { await vm.cancelQuery() }
                }
            } else {
                V2Button(title: "Run Query", systemImage: "play.fill", kind: .primary) {
                    Task { await vm.runQuery() }
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var activeTextBinding: Binding<String> {
        Binding(
            get: { vm.queryText },
            set: { vm.queryText = $0 }
        )
    }

    private var sqlEditor: some View {
        TextEditor(text: activeTextBinding)
            .id(vm.activeQueryTabID)
            .font(.jbMono(12.5))
            .foregroundStyle(KTEditorTheme.label)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(height: 132)
            .background(KTEditorTheme.content)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(KTEditorTheme.separator, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private var resultsArea: some View {
        if let result = vm.queryResult {
            KTDataGrid(result: result)
        } else if vm.isRunning {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(KTEditorTheme.content)
        } else {
            Spacer()
                .frame(maxWidth: .infinity)
                .background(KTEditorTheme.content)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            statusContent
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(KTEditorTheme.content2)
        .overlay(alignment: .top) { Divider().overlay(KTEditorTheme.separator) }
    }

    @ViewBuilder
    private var statusContent: some View {
        if let error = vm.queryError {
            HStack(spacing: 5) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                Text(error).font(.jbMono(11)).lineLimit(1)
            }
            .foregroundStyle(KTEditorTheme.Status.error)
        } else if let result = vm.queryResult {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                Text("\(result.rowCount) rows").font(.jbMono(11))
            }
            .foregroundStyle(KTEditorTheme.Status.running)
        } else if vm.isRunning {
            ProgressView().scaleEffect(0.7)
        } else {
            Text("Ready").font(.jbMono(11)).foregroundStyle(KTEditorTheme.label3)
        }
    }
}
