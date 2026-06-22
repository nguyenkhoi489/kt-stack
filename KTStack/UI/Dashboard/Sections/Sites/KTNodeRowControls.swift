import SwiftUI
import KTStackKit

struct KTNodeStatusBadge: View {
    let state: NodeSiteController.State

    var body: some View {
        HStack(spacing: 6) {
            KTDot(color: state.serviceStatus.color, size: 7)
            Text(state.badgeLabel)
                .font(.jbMono(12.5, .medium))
                .foregroundStyle(KTColor.muted)
        }
        .frame(width: 124, alignment: .leading)
    }
}

struct KTNodeBanner: View {
    let state: NodeSiteController.State
    @Binding var commandDraft: String
    let installing: Bool
    let onSaveCommand: () -> Void
    let onInstall: () -> Void
    let onOpenRuntimes: () -> Void

    var body: some View {
        switch state {
        case .needsRuntime:
            banner(icon: "exclamationmark.triangle.fill", tint: Color.KDStatus.warning,
                   text: "Node runtime is not installed.") {
                KTButton(title: "Download Node", kind: .secondary, action: onOpenRuntimes)
            }
        case .needsCommand:
            banner(icon: "terminal", tint: KTColor.muted,
                   text: "Enter the command that starts this app (it must read process.env.PORT).") {
                HStack(spacing: 8) {
                    TextField("node server.js", text: $commandDraft)
                        .textFieldStyle(.plain)
                        .font(.jbMono(12.5))
                        .foregroundStyle(KTColor.ink)
                        .frame(width: 220)
                        .onSubmit(onSaveCommand)
                    KTButton(title: "Save", kind: .secondary, action: onSaveCommand)
                }
            }
        case .needsInstall:
            banner(icon: "shippingbox", tint: Color.KDStatus.warning,
                   text: "Dependencies are not installed (node_modules missing).") {
                KTButton(title: installing ? "Installing…" : "Run npm install",
                         kind: .secondary, action: onInstall)
                    .disabled(installing)
            }
        case .running, .crashed, .stopped:
            EmptyView()
        }
    }

    @ViewBuilder
    private func banner<Trailing: View>(icon: String, tint: Color, text: String,
                                        @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
            Text(text).font(.jbMono(12)).foregroundStyle(KTColor.muted)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KTColor.pillBg))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
