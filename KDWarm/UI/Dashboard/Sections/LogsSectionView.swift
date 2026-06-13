import SwiftUI
import KDWarmKit

/// Logs viewer (design §5.9): a source picker (service / per-site logs) → virtualized live tail with
/// a severity gutter, a text filter, a "● Live" auto-scroll toggle, and clear. Binds to a
/// `LogTailController` that incrementally tails the selected file into a bounded ring buffer.
struct LogsSectionView: View {
    /// Optional deep-link target (a `LogSource.id`) from a Services/Sites "Logs" action.
    var targetSourceID: String?

    @EnvironmentObject private var server: LocalServerController
    @StateObject private var tail = LogTailController()
    @State private var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let paths = AppSupportPaths()
    private let bottomID = "logs-bottom-anchor"

    private var sources: [LogSource] {
        LogCatalog(paths: paths).sources(
            siteDomains: server.registry.sites.map(\.domain),
            phpVersions: server.availableVersions)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .navigationTitle("Logs")
        .onAppear { selectInitial() }
        .onChange(of: selectedID) { id in tail.select(sources.first { $0.id == id }) }
    }

    private var toolbar: some View {
        HStack(spacing: KDSpacing.space2) {
            Picker("Source", selection: $selectedID) {
                ForEach(sources) { Text($0.displayName).tag(Optional($0.id)) }
            }
            .labelsHidden().frame(maxWidth: 260)

            TextField("Filter", text: $tail.filter)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 200)

            Spacer()

            Toggle(isOn: $tail.isLive) {
                Label("Live", systemImage: tail.isLive ? "dot.radiowaves.left.and.right" : "pause.circle")
            }
            .toggleStyle(.button).controlSize(.small)

            Button { tail.clear() } label: { Image(systemName: "trash") }
                .help("Clear the log — empties both the view and the log file on disk")
        }
        .padding(KDSpacing.space2)
    }

    @ViewBuilder
    private var content: some View {
        if sources.isEmpty {
            EmptyStateView(symbol: "text.alignleft", title: "No logs yet",
                           message: "Start a service to produce logs, then pick a source to tail it here.",
                           actionTitle: nil)
        } else if tail.lines.isEmpty {
            EmptyStateView(symbol: "text.alignleft", title: "No lines",
                           message: "This log is empty or filtered out. New lines stream in live.",
                           actionTitle: nil)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(tail.lines) { LogLineRow(line: $0) }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .padding(.vertical, KDSpacing.space1)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: tail.lines.count) { _ in
                    guard tail.isLive else { return }
                    if reduceMotion { proxy.scrollTo(bottomID, anchor: .bottom) }
                    else { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(bottomID, anchor: .bottom) } }
                }
            }
        }
    }

    private func selectInitial() {
        let available = sources
        if let target = targetSourceID, available.contains(where: { $0.id == target }) {
            selectedID = target
        } else if selectedID == nil {
            selectedID = available.first?.id
        }
        tail.select(available.first { $0.id == selectedID })
    }
}
