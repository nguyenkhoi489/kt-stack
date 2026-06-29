import AppKit
import KTStackKit
import SwiftUI

struct KTSidebar: View {
    @Binding var selection: SidebarItem
    let siteCount: Int
    let serverStatus: ServiceStatus
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: KTMetric.trafficLightInset)
            identity
            group("MANAGE", SidebarSection.manage.items, topPadding: 0)
            group("INSPECT", SidebarSection.inspect.items, topPadding: 18)
            group("APP", SidebarSection.app.items, topPadding: 18)
            Spacer(minLength: 12)
            KTSidebarFooterCard(status: serverStatus, version: version)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 14)
        .frame(width: KTMetric.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(KTColor.sidebarBackground.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(KTColor.hairline).frame(width: KTMetric.hairline)
        }
    }

    private var identity: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: Color(hex: 0x140F28, opacity: 0.4), radius: 4, y: 3)
            Text("KTStack")
                .font(.jbMono(16, .bold))
                .foregroundStyle(KTColor.ink)
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.top, 4)
        .padding(.bottom, 18)
    }

    private func group(_ title: String, _ items: [SidebarItem], topPadding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(KTType.sectionLabel)
                .tracking(KTType.sectionLabelTracking)
                .foregroundStyle(KTColor.muted)
                .padding(.horizontal, 8)
                .padding(.top, topPadding)
                .padding(.bottom, 8)
            ForEach(items) { item in
                KTSidebarRow(
                    item: item,
                    isActive: selection == item,
                    badge: item == .sites ? siteCount : nil,
                    action: { selection = item }
                )
            }
        }
    }
}
