import AppKit
import KTStackKit
import SwiftUI

struct KTSiteShareControls: View {
    var shareStarting: Bool
    var shareURL: URL?
    var shareExpiresAt: Date?
    let onToggleShare: (Bool) -> Void

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 2) {
            if shareStarting {
                ProgressView().controlSize(.small).frame(width: 28, height: 26)
            } else if let shareURL {
                if let shareExpiresAt {
                    Text("Expires \(Self.expiryFormatter.string(from: shareExpiresAt))")
                        .font(.jbMono(11))
                        .foregroundStyle(KTColor.muted)
                        .ktTip("Tunnel closes automatically at this time")
                        .padding(.trailing, 4)
                }
                iconButton("doc.on.doc", help: "Copy tunnel URL", tint: KTColor.ink3) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(shareURL.absoluteString, forType: .string)
                }
                TunnelQRCodeButton(url: shareURL).foregroundStyle(KTColor.accent)
                iconButton(
                    "antenna.radiowaves.left.and.right",
                    help: "Stop sharing via tunnel",
                    tint: KTColor.accent
                ) { onToggleShare(false) }
            } else {
                iconButton(
                    "antenna.radiowaves.left.and.right.slash",
                    help: "Share via tunnel",
                    tint: KTColor.ink3
                ) { onToggleShare(true) }
            }
        }
    }

    private func iconButton(
        _ symbol: String,
        help: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ktTip(help)
    }
}
