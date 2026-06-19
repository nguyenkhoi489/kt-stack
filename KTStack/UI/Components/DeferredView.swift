import SwiftUI
import KTStackKit

struct DeferredView<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var mounted = false

    var body: some View {
        ZStack {
            if mounted {
                content()
            } else {
                KTColor.contentBg
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            mounted = true
        }
    }
}
