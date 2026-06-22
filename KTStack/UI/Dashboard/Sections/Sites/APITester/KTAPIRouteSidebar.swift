import SwiftUI
import KTStackKit

enum KTAPIMethodStyle {
    static func tint(_ method: String) -> KTTint {
        switch method.uppercased() {
        case "GET":    return KTTint(fg: Color(hex: 0x1FA463), bg: Color(hex: 0xE7F8EE))
        case "POST":   return KTTint(fg: Color(hex: 0xC07A00), bg: Color(hex: 0xFFF3DC))
        case "PUT":    return KTTint(fg: Color(hex: 0x2F6BFF), bg: Color(hex: 0xEAF1FF))
        case "PATCH":  return KTTint(fg: Color(hex: 0x8B5CF6), bg: Color(hex: 0xF1ECFF))
        case "DELETE": return KTTint(fg: Color(hex: 0xD93A2E), bg: Color(hex: 0xFFF0EE))
        default:       return KTTint(fg: Color(hex: 0x6B6B76), bg: Color(hex: 0xEFEFF3))
        }
    }
}

struct KTAPIMethodBadge: View {
    let method: String

    var body: some View {
        let tint = KTAPIMethodStyle.tint(method)
        Text(method.uppercased())
            .font(.jbMono(10.5, .bold))
            .foregroundStyle(tint.fg)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint.bg))
    }
}

struct KTAPIRouteSidebar: View {
    @ObservedObject var vm: APITesterViewModel

    var body: some View {
        VStack(spacing: 0) {
            if !vm.isGenericMode { tabs }
            searchField
            newRequestButton
            list
            variablesSection
        }
        .frame(width: 300)
        .background(Color(hex: 0xFBFBFC))
        .overlay(alignment: .trailing) { Rectangle().fill(KTColor.sep).frame(width: 0.5) }
    }

    private var variablesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(KTColor.sep).frame(height: 0.5)
            HStack(spacing: 6) {
                Image(systemName: "curlybraces").font(.system(size: 11)).foregroundStyle(KTColor.muted)
                Text("VARIABLES").font(.jbMono(10.5, .bold)).foregroundStyle(KTColor.ink3)
                Spacer()
                Text(vm.siteDomain).font(.jbMono(10)).foregroundStyle(KTColor.faint).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
            manageButton
        }
        .background(Color.white)
    }

    private var manageButton: some View {
        Button { vm.isEditingVariables = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 13))
                Text("Manage variables").font(.jbMono(12.5, .medium))
                Spacer()
                Text("\(vm.activeVariableCount)")
                    .font(.jbMono(11, .bold)).foregroundStyle(KTColor.accent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white))
            }
            .foregroundStyle(KTColor.accent)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KTColor.accentSoft))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    private var newRequestButton: some View {
        Button { vm.newRequest() } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle.fill").font(.system(size: 13))
                Text("New request").font(.jbMono(12.5, .medium))
                Spacer()
            }
            .foregroundStyle(KTColor.accent)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KTColor.accentSoft))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var tabs: some View {
        KTSegmentedTabs(items: [.init(value: RouteTab.web, label: "Web"),
                                .init(value: .api, label: "API")],
                        selection: $vm.tab)
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(KTColor.muted)
            TextField("Filter routes…", text: $vm.filter)
                .textFieldStyle(.plain)
                .font(.jbMono(13))
                .foregroundStyle(KTColor.ink)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color(hex: 0xE6E6EC), lineWidth: 0.5))
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    @ViewBuilder
    private var list: some View {
        if vm.isLoadingRoutes {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading routes…").font(.jbMono(12)).foregroundStyle(KTColor.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.visibleRoutes.isEmpty {
            Text(emptyMessage)
                .font(.jbMono(12)).foregroundStyle(KTColor.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(vm.visibleRoutes) { route in
                        row(route)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
            }
        }
    }

    private var emptyMessage: String {
        if vm.isGenericMode { return "Compose a request above, or hit New request." }
        return vm.routes.isEmpty ? "No routes" : "No routes in this group"
    }

    private func row(_ route: APIRoute) -> some View {
        let active = vm.selected?.id == route.id
        return Button { vm.select(route) } label: {
            HStack(spacing: 9) {
                KTAPIMethodBadge(method: route.method).frame(width: 52, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(route.uri)
                        .font(.jbMono(12.5))
                        .foregroundStyle(active ? KTColor.accent : KTColor.ink2)
                        .lineLimit(1)
                    if let name = route.name {
                        Text(name).font(.jbMono(10.5)).foregroundStyle(KTColor.faint).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(active ? KTColor.accentSoft : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
