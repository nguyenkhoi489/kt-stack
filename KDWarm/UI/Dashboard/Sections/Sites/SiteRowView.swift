import SwiftUI
import AppKit
import KDWarmKit


struct SiteRowView: View {
    let site: Site
    let availableVersions: [String]
    let canOpen: Bool
    let onOpen: () -> Void
    let onRemove: () -> Void
    let onEditDomain: (String) throws -> Void
    let onSetVersion: (String) -> Void
    let onSetSecure: (Bool) -> Void
    let onOpenLogs: () -> Void
    let shareStatus: TunnelStatus
    let onToggleShare: (Bool) -> Void

    @State private var domainDraft: String
    @State private var domainError: String?
    @State private var didCopy = false
    @State private var debugConfigError: String?

    init(site: Site, availableVersions: [String], canOpen: Bool,
         onOpen: @escaping () -> Void, onRemove: @escaping () -> Void,
         onEditDomain: @escaping (String) throws -> Void, onSetVersion: @escaping (String) -> Void,
         onSetSecure: @escaping (Bool) -> Void, onOpenLogs: @escaping () -> Void,
         shareStatus: TunnelStatus = .idle, onToggleShare: @escaping (Bool) -> Void = { _ in }) {
        self.site = site
        self.availableVersions = availableVersions
        self.canOpen = canOpen
        self.onOpen = onOpen
        self.onRemove = onRemove
        self.onEditDomain = onEditDomain
        self.onSetVersion = onSetVersion
        self.onSetSecure = onSetSecure
        self.onOpenLogs = onOpenLogs
        self.shareStatus = shareStatus
        self.onToggleShare = onToggleShare
        _domainDraft = State(initialValue: site.domain)
    }

    var body: some View {
        HStack(spacing: KDSpacing.space2) {
            Image(systemName: site.type.symbolName)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(site.name).font(KDFont.body)
                TextField("domain", text: $domainDraft)
                    .font(KDFont.mono)
                    .textFieldStyle(.plain)
                    .foregroundStyle(domainError == nil ? .secondary : Color.KDStatus.error)
                    .onSubmit(commitDomain)
                if let domainError {
                    Text(domainError).font(KDFont.footnote).foregroundStyle(Color.KDStatus.error)
                }
            }

            Spacer()

            if site.type == .php { phpVersionMenu }

            Image(systemName: site.secure ? "lock.fill" : "lock.open")
                .font(.footnote)
                .foregroundStyle(site.secure ? Color.KDStatus.running : .secondary)
            Toggle("Secure", isOn: Binding(get: { site.secure }, set: onSetSecure))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .help("Serve over HTTPS with a locally-trusted certificate")

            shareControl

            Button("Open", action: onOpen).disabled(!canOpen)

            Menu {
                Button("Open in Browser", action: onOpen).disabled(!canOpen)
                Button("Reveal in Finder") { revealInFinder() }
                Button("Open Terminal Here") { openTerminal() }
                Button("Logs", action: onOpenLogs)
                if site.type == .php {
                    Button("Configure VS Code Debug") { configureVSCode() }
                }
                Divider()
                Button("Remove Site", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).frame(width: 28)
        }
        .padding(.vertical, KDSpacing.space2)
        .padding(.horizontal, KDSpacing.space2)
        .onChange(of: site.domain) { new in domainDraft = new; domainError = nil }
        .alert("Configure VS Code Debug Failed", isPresented: Binding(
            get: { debugConfigError != nil },
            set: { if !$0 { debugConfigError = nil } })) {
                Button("OK", role: .cancel) { debugConfigError = nil }
            } message: {
                Text(debugConfigError ?? "")
            }
    }

    @ViewBuilder
    private var shareControl: some View {
        switch shareStatus {
        case .idle, .expired:
            Button { onToggleShare(true) } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.borderless)
            .help(shareStatus == .expired ? "Tunnel expired — share again" : "Share via public tunnel")
        case .starting:
            ProgressView().controlSize(.small)
        case .active(let url):
            activeControls(url: url, unverified: false)
        case .activeUnverified(let url):
            activeControls(url: url, unverified: true)
        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.KDStatus.error)
                Text(message)
                    .font(KDFont.footnote)
                    .foregroundStyle(Color.KDStatus.error)
                    .lineLimit(2)
                    .help(message)
                Button { onToggleShare(true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Share again")
            }
        }
    }

    private func activeControls(url: URL, unverified: Bool) -> some View {
        HStack(spacing: 4) {
            if unverified {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.KDStatus.warning)
                    .help("Couldn't verify the link from this machine (restricted network). Test it from another network — it may still work for visitors.")
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Color.KDStatus.warning)
            }
            Text(url.host ?? url.absoluteString).font(KDFont.footnote).lineLimit(1)
            Button { copy(url) } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
            }.buttonStyle(.borderless).help("Copy public URL")
            Button { onToggleShare(false) } label: {
                Image(systemName: "stop.circle")
            }.buttonStyle(.borderless).help("Stop sharing")
        }
    }

    private func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
    }

    private var phpVersionMenu: some View {
        Menu {
            ForEach(availableVersions, id: \.self) { v in
                Button(v) { onSetVersion(v) }
            }
        } label: {
            Text("PHP \(site.phpVersion)").font(KDFont.footnote)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func commitDomain() {
        let next = domainDraft.trimmingCharacters(in: .whitespaces).lowercased()
        guard next != site.domain else { domainError = nil; return }
        do { try onEditDomain(next); domainError = nil }
        catch { domainError = error.localizedDescription; domainDraft = site.domain }
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: site.path)])
    }

    private func openTerminal() {
        let url = URL(fileURLWithPath: site.path)
        let term = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([url], withApplicationAt: term,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    private func configureVSCode() {
        do {
            let written = try IDEDebugConfigWriter().writeVSCode(
                projectRoot: URL(fileURLWithPath: site.path),
                docroot: URL(fileURLWithPath: site.docroot))
            NSWorkspace.shared.activateFileViewerSelecting([written])
        } catch {
            debugConfigError = error.localizedDescription
        }
    }
}
