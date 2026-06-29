import KTStackKit
import SwiftUI

struct KTSidebarFooterCard: View {
    let status: ServiceStatus
    let version: String

    var body: some View {
        HStack(spacing: 10) {
            KTDot(color: dotColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Server \(status.label)")
                    .font(.jbMono(13, .regular))
                    .foregroundStyle(KTColor.ink)
                Text("v\(version)")
                    .font(.jbMono(11.5))
                    .foregroundStyle(KTColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color(hex: 0xE8E8EE), lineWidth: 0.5))
    }

    private var dotColor: Color {
        switch status {
        case .running: KTColor.runDot
        case .starting: KTColor.accent
        case .error: KTColor.danger
        case .warning: Color(hex: 0xFF9F0A)
        default: KTColor.stopDot
        }
    }
}
