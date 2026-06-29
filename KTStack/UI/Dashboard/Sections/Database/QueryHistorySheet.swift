import KTStackKit
import SwiftUI

struct QueryHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vm: DatabaseViewModel
    let onPick: (QueryHistoryEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640, height: 460)
    }

    private var header: some View {
        HStack {
            Text("Query History").font(KDFont.title)
            Spacer()
            Button { vm.clearQueryHistory() } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(vm.queryHistoryEntries.isEmpty)
        }
        .padding(KDSpacing.space3)
    }

    @ViewBuilder
    private var content: some View {
        if vm.queryHistoryEntries.isEmpty {
            EmptyStateView(
                symbol: "clock.arrow.circlepath",
                title: "No query history",
                message: "Run SQL to build a local recall list."
            )
        } else {
            List(vm.queryHistoryEntries) { entry in
                Button {
                    onPick(entry)
                    dismiss()
                } label: {
                    historyRow(entry)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
        }
        .padding(KDSpacing.space3)
    }

    private func historyRow(_ entry: QueryHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: KDSpacing.space1) {
            Text(entry.sql)
                .font(KDFont.mono)
                .lineLimit(2)
            HStack(spacing: KDSpacing.space2) {
                Text(entry.connectionLabel)
                if let database = entry.database {
                    Text(database)
                }
                Text(entry.ranAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(KDFont.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, KDSpacing.space1)
    }
}
