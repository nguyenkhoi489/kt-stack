import KTStackKit
import SwiftUI

struct KTSitesHeader: View {
    let siteCount: Int
    let onScan: () -> Void
    let onNewSite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Sites")
                .font(KTType.screenTitle)
                .tracking(KTType.screenTitleTracking)
                .foregroundStyle(KTColor.ink)
            KTPill(text: "\(siteCount) sites")
            Spacer()
            KTButton(title: "Scan", systemImage: "arrow.triangle.2.circlepath", kind: .secondary, action: onScan)
            newSiteButton
        }
    }

    private var newSiteButton: some View {
        Button(action: onNewSite) {
            HStack(spacing: 7) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                Text("New Site").font(.jbMono(13, .regular))
            }
            .foregroundStyle(.white)
            .padding(.vertical, 9)
            .padding(.horizontal, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .background(KTColor.accentGradient)
        .clipShape(RoundedRectangle(cornerRadius: KTRadius.button, style: .continuous))
    }
}
