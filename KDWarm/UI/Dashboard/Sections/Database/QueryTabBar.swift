import SwiftUI
import KDWarmKit

struct QueryTabBar: View {
    @EnvironmentObject private var vm: DatabaseViewModel

    var body: some View {
        HStack(spacing: KDSpacing.space1) {
            ForEach(vm.queryTabs) { tab in
                tabButton(tab)
            }
            Button { vm.addQueryTab() } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New query tab")
            Spacer()
        }
        .padding(.horizontal, KDSpacing.space2)
        .padding(.vertical, KDSpacing.space1)
    }

    private func tabButton(_ tab: QueryTab) -> some View {
        HStack(spacing: KDSpacing.space1) {
            Button { vm.selectQueryTab(tab.id) } label: {
                HStack(spacing: KDSpacing.space1) {
                    if tab.isBusy {
                        ProgressView().controlSize(.mini)
                    }
                    Text(tab.title).lineLimit(1)
                }
            }
            .buttonStyle(.borderless)
            Button { vm.closeQueryTab(tab.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Close query tab")
        }
        .font(KDFont.footnote)
        .padding(.vertical, 3)
        .padding(.horizontal, KDSpacing.space2)
        .background(tab.id == vm.activeQueryTabID ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
