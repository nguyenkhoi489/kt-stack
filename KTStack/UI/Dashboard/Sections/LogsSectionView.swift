import SwiftUI
import KTStackKit

struct LogsSectionView: View {

    var targetSourceID: String?

    @EnvironmentObject private var server: LocalServerController
    @StateObject private var tail = LogTailController()
    @State private var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let paths = AppSupportPaths()
    private let bottomID = "logs-bottom-anchor"

    private var sources: [LogSource] {
        LogCatalog(paths: paths).sources(
            siteDomains: server.registry.sites.map(\.domain),
            phpVersions: server.availableVersions)
    }

    private var currentSourceName: String {
        sources.first { $0.id == selectedID }?.displayName ?? "All sites"
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, KTSpacing.screenGutter).padding(.top, 18)
            logPanel.padding(.horizontal, KTSpacing.screenGutter).padding(.top, 16).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(KTColor.contentBg)
        .onAppear { selectInitial() }
        .onChange(of: selectedID) { id in tail.select(sources.first { $0.id == id }) }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Text("Logs").font(KTType.screenTitle).tracking(KTType.screenTitleTracking).foregroundStyle(KTColor.ink)
            Spacer()
            sourceMenu
            Button(action: { tail.clear() }) {
                Text("Clear").font(.system(size: 13, weight: .medium)).foregroundStyle(KTColor.ink)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(KTColor.btnBorder, lineWidth: 0.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            followToggle
        }
    }

    private var sourceMenu: some View {
        Menu {
            ForEach(sources) { source in
                Button(source.displayName) { selectedID = source.id }
            }
        } label: {
            HStack(spacing: 7) {
                Text(currentSourceName).font(.system(size: 13, weight: .medium)).foregroundStyle(KTColor.ink).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(KTColor.muted)
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(KTColor.btnBorder, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var followToggle: some View {
        Button(action: { tail.isLive.toggle() }) {
            HStack(spacing: 7) {
                if tail.isLive {
                    Circle().fill(KTColor.runDot).frame(width: 7, height: 7)
                    Text("Following").font(.system(size: 13, weight: .semibold)).foregroundStyle(KTColor.online)
                } else {
                    Image(systemName: "pause.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(KTColor.ink3)
                    Text("Paused").font(.system(size: 13, weight: .medium)).foregroundStyle(KTColor.ink2)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tail.isLive ? KTColor.onlineBg : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(tail.isLive ? Color.clear : KTColor.btnBorder, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var logPanel: some View {
        if sources.isEmpty {
            emptyPanel("No logs yet", "Start a service to produce logs, then pick a source to tail it here.")
        } else if tail.lines.isEmpty {
            emptyPanel("No lines", "This log is empty or filtered out. New lines stream in live.")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(tail.lines) { line in logRow(line) }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(KTColor.editorBg))
                .onChange(of: tail.lines.count) { _ in
                    guard tail.isLive else { return }
                    if reduceMotion { proxy.scrollTo(bottomID, anchor: .bottom) }
                    else { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(bottomID, anchor: .bottom) } }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func logRow(_ line: LogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(severityLabel(line.severity))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(severityColor(line.severity))
                .frame(width: 42, alignment: .leading)
            Text(line.text)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Color(hex: 0xD4D4DA))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private func severityLabel(_ severity: LogSeverity) -> String {
        switch severity {
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }

    private func severityColor(_ severity: LogSeverity) -> Color {
        switch severity {
        case .info: return Color(hex: 0x7FD4A0)
        case .warning: return Color(hex: 0xFFD479)
        case .error: return Color(hex: 0xFF8FB0)
        }
    }

    private func emptyPanel(_ title: String, _ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "text.alignleft").font(.system(size: 42, weight: .light)).foregroundStyle(KTColor.faint)
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(KTColor.ink3)
            Text(message).font(.system(size: 13)).foregroundStyle(KTColor.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectInitial() {
        let available = sources
        if let target = targetSourceID, available.contains(where: { $0.id == target }) {
            selectedID = target
        } else if selectedID == nil {
            selectedID = available.first?.id
        }
        tail.select(available.first { $0.id == selectedID })
    }
}
