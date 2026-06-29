import KTStackKit
import SwiftUI

struct KTSitesDNSFooter: View {
    @ObservedObject var dns: DNSAutomationService
    let tld: String

    var body: some View {
        HStack(spacing: 12) {
            KTIconTile(tint: KTIconTint.globe, size: 30, radius: 9) {
                Image(systemName: "checkmark.shield").font(.system(size: 14, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.jbMono(13, .regular)).foregroundStyle(KTColor.ink)
                Text(subtitle).font(.jbMono(12)).foregroundStyle(KTColor.muted)
            }
            Spacer()
            if dns.isBusy {
                ProgressView().controlSize(.small)
            } else {
                KTButton(title: "Reset", kind: .secondary) { dns.reset() }
                if dns.isEnabled {
                    KTButton(title: "Disable DNS", kind: .danger) { dns.disable() }
                } else {
                    KTButton(title: "Enable DNS", kind: .secondary) { dns.enable() }
                }
            }
        }
        .padding(.horizontal, KTSpacing.screenGutter)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(KTColor.sep).frame(height: 0.5) }
    }

    private var title: String {
        dns.isEnabled ? "Automatic DNS is on" : "Automatic DNS is off"
    }

    private var subtitle: String {
        dns.isEnabled ? "*.\(tld) resolves to this machine." : "Enable DNS to resolve *.\(tld) domains."
    }
}
