import AppKit
import KTStackKit
import SwiftUI

private final class MenuBarPopoverDismisser: ObservableObject {
    weak var window: NSWindow?

    func dismiss() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.resignKey()
            self?.window?.orderOut(nil)
        }
    }
}

private struct MenuBarWindowReader: NSViewRepresentable {
    let dismisser: MenuBarPopoverDismisser

    func makeNSView(context _: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async { dismisser.window = nsView.window }
    }
}

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var server: LocalServerController
    @EnvironmentObject private var services: ServiceManager
    @EnvironmentObject private var updater: UpdaterController
    @StateObject private var dismisser = MenuBarPopoverDismisser()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, KDSpacing.space1)
            servicesSection
            Divider().padding(.vertical, KDSpacing.space1)
            MenuBarVersionSwitcher()
            Divider().padding(.vertical, KDSpacing.space1)
            footer
        }
        .padding(KDSpacing.space2)
        .frame(width: 324)
        .background(MenuBarWindowReader(dismisser: dismisser))
    }

    private var anyRunning: Bool {
        services.snapshots.contains { $0.status == .running }
    }

    private var header: some View {
        HStack(spacing: KDSpacing.space2) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("KTStack").font(KDFont.headline)
                Text(headerSubtitle)
                    .font(KDFont.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(anyRunning ? "Stop All" : "Start All") {
                anyRunning ? services.stopAll() : services.startAll()
            }
            .buttonStyle(.borderless)
            .font(KDFont.footnote)
        }
        .padding(.horizontal, KDSpacing.space1)
    }

    private var headerSubtitle: String {
        let running = services.snapshots.filter { $0.status == .running }.count
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        return "v\(version) · \(running) of \(services.snapshots.count) running"
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space1) {
            Text("Services")
                .font(KDFont.footnote)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, KDSpacing.space1)

            ForEach(services.snapshots) { snapshot in
                serviceRow(snapshot)
            }
        }
    }

    private func serviceRow(_ snapshot: ServiceSnapshot) -> some View {
        let canToggle = snapshot.isInstalled
        let binding = Binding<Bool>(
            get: { snapshot.status == .running },
            set: { _ in services.toggle(snapshot.kind) }
        )
        return HStack(spacing: KDSpacing.space2) {
            Image(systemName: snapshot.symbolName)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(snapshot.displayName).font(KDFont.body)
            Spacer()
            StatusPill(snapshot.status, text: pillText(snapshot))
            if snapshot.isBusy {
                ProgressView().controlSize(.mini).frame(width: 28)
            } else {
                Toggle("", isOn: binding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(!canToggle)
            }
        }
        .padding(.vertical, KDSpacing.space1)
        .padding(.horizontal, KDSpacing.space1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.displayName), \(snapshot.status.label), \(pillText(snapshot))")
    }

    private func pillText(_ snapshot: ServiceSnapshot) -> String {
        snapshot.isInstalled ? (snapshot.detail.isEmpty ? snapshot.status.label : snapshot.detail)
            : "Not installed"
    }

    private var footer: some View {
        VStack(spacing: 0) {
            footerButton("Open Dashboard…", systemImage: "rectangle.split.3x1", shortcut: "⌘D") {
                AppActivationPolicy.activateRegular()
                if !AppActivationPolicy.focusExistingWindow(titled: "KTStack Dashboard") {
                    openWindow(id: DashboardWindow.windowID)
                }
                dismisser.dismiss()
            }
            settingsFooterItem
            #if DEBUG
                footerButton("SQL Editor Drafts", systemImage: "paintbrush.pointed", shortcut: "") {
                    SQLEditorDraftsWindowController.shared.present()
                    dismisser.dismiss()
                }
            #endif
            footerButton("Check for Updates…", systemImage: "arrow.down.circle", shortcut: "") {
                AppActivationPolicy.activateRegular()
                updater.checkForUpdates()
                dismisser.dismiss()
            }
            footerButton("Quit KTStack", systemImage: "power", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private var settingsFooterItem: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                footerRowLabel("Settings…", systemImage: "gearshape", shortcut: "⌘,")
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                AppActivationPolicy.activateRegular()
                dismisser.dismiss()
            })
        } else {
            footerButton("Settings…", systemImage: "gearshape", shortcut: "⌘,") {
                AppActivationPolicy.activateRegular()
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                dismisser.dismiss()
            }
        }
    }

    private func footerButton(
        _ title: String,
        systemImage: String,
        shortcut: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            footerRowLabel(title, systemImage: systemImage, shortcut: shortcut)
        }
        .buttonStyle(.plain)
    }

    private func footerRowLabel(
        _ title: String,
        systemImage: String,
        shortcut: String
    ) -> some View {
        HStack(spacing: KDSpacing.space2) {
            Image(systemName: systemImage).frame(width: 18).foregroundStyle(.secondary)
            Text(title).font(KDFont.body)
            Spacer()
            Text(shortcut).font(KDFont.footnote).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, KDSpacing.space1)
        .padding(.horizontal, KDSpacing.space1)
    }
}
