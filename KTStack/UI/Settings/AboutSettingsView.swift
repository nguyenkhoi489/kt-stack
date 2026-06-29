import AppKit
import KTStackKit
import SwiftUI

struct AboutSettingsView: View {
    @EnvironmentObject private var updater: UpdaterController

    private var versionLine: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let buildPart = build.isEmpty ? "" : " · Build \(build)"
        return "Version \(short)\(buildPart) · Minh Trang"
    }

    var body: some View {
        VStack(spacing: 0) {
            appIcon
            Text("KTStack").font(.jbMono(24, .bold)).tracking(-0.6).foregroundStyle(KTColor.ink)
                .padding(.top, 20)
            Text(versionLine).font(.jbMono(14)).foregroundStyle(Color(hex: 0x8E8E93)).padding(.top, 6)
            Text("A blazing-fast local development environment for macOS. Run unlimited sites, switch PHP & Node versions instantly, and inspect everything in one place.")
                .font(.jbMono(15)).foregroundStyle(KTColor.ink2)
                .multilineTextAlignment(.center).lineSpacing(4).frame(maxWidth: 420).padding(.top, 18)
            checkButton.padding(.top, 24)
            linkRow.padding(.top, 26)
            Text("© 2026 KTStack. Built with ❤️ by Nguyên Khôi")
                .font(.jbMono(12)).foregroundStyle(Color(hex: 0xB0B0B8)).padding(.top, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(KTColor.contentBg)
    }

    private var appIcon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable().interpolation(.high)
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color(hex: 0x140F28, opacity: 0.5), radius: 17, y: 8)
    }

    private var checkButton: some View {
        Button { updater.checkForUpdates() } label: {
            Text("Check for Updates").font(.jbMono(14, .regular)).foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KTColor.accentGradient))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!updater.canCheckForUpdates)
        .opacity(updater.canCheckForUpdates ? 1 : 0.6)
    }

    private var linkRow: some View {
        HStack(spacing: 22) {
            link("Website", "https://github.com/KTStackAPP/KTStack")
            link("Documentation", "https://github.com/KTStackAPP/KTStack#readme")
            link("Release Notes", "https://github.com/KTStackAPP/KTStack/releases")
            link("GitHub", "https://github.com/KTStackAPP/KTStack")
        }
    }

    private func link(_ title: String, _ url: String) -> some View {
        Button {
            if let target = URL(string: url) { NSWorkspace.shared.open(target) }
        } label: {
            Text(title).font(.jbMono(13.5, .medium)).foregroundStyle(KTColor.accent)
        }
        .buttonStyle(.plain)
    }
}
