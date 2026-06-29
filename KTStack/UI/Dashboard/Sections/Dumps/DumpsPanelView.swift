import KTStackKit
import SwiftUI

struct DumpsPanelView: View {
    @EnvironmentObject private var server: LocalServerController
    @StateObject private var model = DumpsViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let bottomID = "dumps-bottom-anchor"

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, KTSpacing.screenGutter).padding(.top, 18)
            content.padding(.horizontal, KTSpacing.screenGutter).padding(.top, 16).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(KTColor.contentBg)
        .onAppear { model.configure(server: server) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Dumps").font(KTType.screenTitle).tracking(KTType.screenTitleTracking).foregroundStyle(KTColor.ink)
            Text("\(model.events.count) captured")
                .font(.jbMono(12.5, .regular)).foregroundStyle(Color(hex: 0x8E8E93))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(KTColor.pillBg))
            Spacer()
            captureToggle
            autoScrollToggle
            Button(action: { model.clear() }) {
                Text("Clear all").font(.jbMono(13, .medium)).foregroundStyle(KTColor.ink)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(KTColor.btnBorder, lineWidth: 0.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.events.isEmpty)
            .opacity(model.events.isEmpty ? 0.5 : 1)
        }
    }

    private var captureToggle: some View {
        Button(action: { model.toggle(!model.enabled) }) {
            HStack(spacing: 7) {
                if model.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Circle().fill(model.enabled ? KTColor.runDot : KTColor.stopDot).frame(width: 7, height: 7)
                }
                Text(model.enabled ? "Capturing" : "Capture off")
                    .font(.jbMono(13, .regular))
                    .foregroundStyle(model.enabled ? KTColor.online : KTColor.ink2)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(model.enabled ? KTColor.onlineBg : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(model.enabled ? Color.clear : KTColor.btnBorder, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
    }

    private var autoScrollToggle: some View {
        Button(action: { model.autoScroll.toggle() }) {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(model.autoScroll ? KTColor.accent : KTColor.ink3)
                .frame(width: 32, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(model.autoScroll ? KTColor.accentSoft : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(model.autoScroll ? Color.clear : KTColor.btnBorder, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Auto-scroll to newest dump")
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.errorMessage {
            messageState(icon: "exclamationmark.triangle", title: "Capture error", message: error, danger: true)
        } else if model.events.isEmpty {
            messageState(
                icon: "curlybraces",
                title: "No dumps yet",
                message: model.enabled
                    ? "Listening for dump() and dd() calls from your PHP app."
                    : "Toggle capture on, then call dump() or dd() in your Laravel or Symfony app.",
                danger: false
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.events) { event in dumpCard(event) }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                }
                .onChange(of: model.events.count) { _ in
                    guard model.autoScroll else { return }
                    if reduceMotion { proxy.scrollTo(bottomID, anchor: .bottom) }
                    else { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(bottomID, anchor: .bottom) } }
                }
            }
        }
    }

    private func dumpCard(_ event: DumpEvent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                typeChip(event.root)
                Text(event.sourceDisplay)
                    .font(.jbMono(13, .regular)).foregroundStyle(KTColor.ink2)
                Spacer()
                Text(Self.timeFormatter.string(from: event.timestamp))
                    .font(.jbMono(12)).foregroundStyle(KTColor.muted)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Color(hex: 0xFAFAFC))
            .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sepFaint).frame(height: 0.5) }
            DumpTreeView(event.root)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(KTColor.sep, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func typeChip(_ node: DumpNode) -> some View {
        let info = typeInfo(node)
        return Text(info.0)
            .font(.jbMono(11, .bold))
            .foregroundStyle(info.1.fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(info.1.bg))
    }

    private func typeInfo(_ node: DumpNode) -> (String, KTTint) {
        switch node {
        case .scalar: ("value", KTIconTint.neutral)
        case .array: ("array", KTIconTint.code)
        case let .object(className, _): (className, KTIconTint.cube)
        case .reference: ("ref", KTIconTint.db)
        }
    }

    private func messageState(icon: String, title: String, message: String, danger: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 42, weight: .light))
                .foregroundStyle(danger ? KTColor.danger : KTColor.faint)
            Text(title).font(.jbMono(16, .regular)).foregroundStyle(KTColor.ink3)
            Text(message).font(.jbMono(13)).foregroundStyle(KTColor.muted).multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
