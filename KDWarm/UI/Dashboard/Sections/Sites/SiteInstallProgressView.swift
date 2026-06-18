import SwiftUI
import KDWarmKit

struct SiteInstallProgressView: View {
    let events: [InstallEvent]
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space2) {
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                Label(event.message, systemImage: glyph(for: event.phase))
                    .font(KDFont.footnote)
                    .foregroundStyle(event.phase == .done ? Color.KDStatus.running : .secondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(KDFont.footnote).foregroundStyle(Color.KDStatus.error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func glyph(for phase: InstallPhase) -> String {
        switch phase {
        case .preparing:          return "shippingbox"
        case .configuringDatabase: return "cylinder.split.1x2"
        case .scaffolding:        return "hammer"
        case .finalizing:         return "globe"
        case .done:               return "checkmark.circle"
        }
    }
}
