import SwiftUI
import KDWarmKit

struct DumpsPanelView: View {
    @EnvironmentObject private var server: LocalServerController
    @StateObject private var model = DumpsViewModel()

    private let bottomID = "dumps-bottom-anchor"

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .navigationTitle("Dumps")
        .onAppear { model.configure(server: server) }
    }

    private var toolbar: some View {
        HStack(spacing: KDSpacing.space2) {
            Toggle(isOn: Binding(
                get: { model.enabled },
                set: { model.toggle($0) }
            )) {
                HStack(spacing: KDSpacing.space1) {
                    Text("Capture dumps").font(KDFont.body)
                    if model.busy {
                        ProgressView().controlSize(.small)
                    } else if model.enabled {
                        StatusPill(.running, text: "on")
                    } else {
                        StatusPill(.stopped, text: "off")
                    }
                }
            }
            .disabled(model.busy)

            Spacer()

            Toggle(isOn: $model.autoScroll) {
                Label("Auto-scroll", systemImage: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .controlSize(.small)

            Button { model.clear() } label: {
                Image(systemName: "trash")
            }
            .help("Clear all dump events")
            .disabled(model.events.isEmpty)
        }
        .padding(KDSpacing.space2)
    }

    @ViewBuilder
    private var content: some View {
        if let err = model.errorMessage {
            VStack(spacing: KDSpacing.space2) {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(KDFont.footnote)
                    .foregroundStyle(Color.KDStatus.error)
                    .multilineTextAlignment(.center)
            }
            .padding(KDSpacing.space4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.events.isEmpty {
            EmptyStateView(
                symbol: "curlybraces",
                title: "No dumps yet",
                message: model.enabled
                    ? "Listening for dump() and dd() calls from your PHP app."
                    : "Toggle capture on, then call dump() or dd() in your Laravel or Symfony app.",
                actionTitle: nil
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.events) { event in
                            DumpEventRow(event: event)
                            Divider()
                        }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: model.events.count) { _ in
                    guard model.autoScroll else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
        }
    }
}
