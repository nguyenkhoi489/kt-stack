import KTStackKit
import SwiftUI

struct KTAPITesterModal: View {
    let site: Site
    let onClose: () -> Void

    @StateObject private var vm = APITesterViewModel()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                KTColor.modalScrim.ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                card
                    .frame(
                        width: min(1180, geo.size.width - 56),
                        height: min(760, geo.size.height - 56)
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await vm.load(site: site) }
    }

    private var card: some View {
        VStack(spacing: 0) {
            headerBar
            if let warning = vm.metadataWarning {
                metadataBanner(warning)
            }
            body(for: vm.loadError)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .ktTooltipHost()
        .background(escCatcher)
        .sheet(isPresented: $vm.isEditingVariables) {
            KTAPIVariablesSheet(vm: vm, site: site)
        }
    }

    @ViewBuilder
    private func body(for loadError: String?) -> some View {
        if let loadError, vm.routes.isEmpty, !vm.isLoadingRoutes {
            errorState(loadError)
        } else {
            HStack(spacing: 0) {
                KTAPIRouteSidebar(vm: vm)
                KTAPIRequestPanel(vm: vm, site: site)
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 13) {
            KTIconTile(tint: KTIconTint.globe, size: 30, radius: 8) {
                Image(systemName: "network").font(.system(size: 15, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(site.name).font(.jbMono(15, .bold)).foregroundStyle(KTColor.ink)
                Text(site.domain).font(.jbMono(12)).foregroundStyle(KTColor.muted)
            }
            Spacer()
            if vm.isLoadingRoutes {
                ProgressView().controlSize(.small)
            } else {
                Text(vm.isGenericMode ? "REST client" : "\(vm.routes.count) routes")
                    .font(.jbMono(12)).foregroundStyle(KTColor.faint)
            }
            closeButton
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(LinearGradient(colors: [Color(hex: 0xFBFBFD), .white], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sep).frame(height: 0.5) }
    }

    private func metadataBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
            Text(text).font(.jbMono(12))
            Spacer()
        }
        .foregroundStyle(Color(hex: 0xC07A00))
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color(hex: 0xFFF3DC))
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.octagon").font(.system(size: 30)).foregroundStyle(KTColor.danger)
            Text("Could not load routes").font(.jbMono(14, .bold)).foregroundStyle(KTColor.ink)
            Text(message).font(.jbMono(12)).foregroundStyle(KTColor.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            KTButton(title: "Retry", systemImage: "arrow.clockwise") {
                Task { await vm.load(site: site) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
                .foregroundStyle(KTColor.muted).frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var escCatcher: some View {
        Button(action: onClose) { Color.clear }
            .keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}
