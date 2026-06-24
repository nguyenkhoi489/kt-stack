import SwiftUI
import AppKit
import KTStackKit

struct KTSiteListRow: View {
    let site: Site
    let availableVersions: [String]
    let canOpen: Bool
    let isSharing: Bool
    var shareStarting: Bool = false
    var shareURL: URL? = nil
    let onOpen: () -> Void
    let onSetVersion: (String) -> Void
    let onSetSecure: (Bool) -> Void
    let onEditDomain: (String) throws -> Void
    let onOpenLogs: () -> Void
    let onToggleShare: (Bool) -> Void
    let onRemove: () -> Void
    var onError: (String) -> Void = { _ in }
    var onOpenRuntimes: () -> Void = {}
    var onRestore: () -> Void = {}

    @EnvironmentObject private var server: LocalServerController
    @State private var domainDraft: String
    @State private var domainError = false
    @State private var hovering = false
    @State private var nodeState: NodeSiteController.State = .stopped
    @State private var nodeCommandDraft: String
    @State private var nodeInstalling = false
    @State private var phpFramework: PHPFramework = .plain

    init(site: Site, availableVersions: [String], canOpen: Bool, isSharing: Bool,
         shareStarting: Bool = false, shareURL: URL? = nil,
         onOpen: @escaping () -> Void, onSetVersion: @escaping (String) -> Void,
         onSetSecure: @escaping (Bool) -> Void, onEditDomain: @escaping (String) throws -> Void,
         onOpenLogs: @escaping () -> Void, onToggleShare: @escaping (Bool) -> Void,
         onRemove: @escaping () -> Void, onError: @escaping (String) -> Void = { _ in },
         onOpenRuntimes: @escaping () -> Void = {}, onRestore: @escaping () -> Void = {}) {
        self.site = site
        self.availableVersions = availableVersions
        self.canOpen = canOpen
        self.isSharing = isSharing
        self.shareStarting = shareStarting
        self.shareURL = shareURL
        self.onOpen = onOpen
        self.onSetVersion = onSetVersion
        self.onSetSecure = onSetSecure
        self.onEditDomain = onEditDomain
        self.onOpenLogs = onOpenLogs
        self.onToggleShare = onToggleShare
        self.onRemove = onRemove
        self.onError = onError
        self.onOpenRuntimes = onOpenRuntimes
        self.onRestore = onRestore
        _domainDraft = State(initialValue: site.domain)
        _nodeCommandDraft = State(initialValue: site.nodeCommand ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if site.type == .node {
                KTNodeBanner(state: nodeState, commandDraft: $nodeCommandDraft,
                             installing: nodeInstalling,
                             onSaveCommand: saveNodeCommand, onInstall: installNodeDeps,
                             onOpenRuntimes: onOpenRuntimes)
            }
        }
        .background(hovering ? KTColor.rowHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .task(id: nodePollKey) { await pollNodeState() }
        .task(id: site.path) { await detectFramework() }
        .onChange(of: site.domain) { new in domainDraft = new; domainError = false }
        .onChange(of: site.nodeCommand) { new in nodeCommandDraft = new ?? "" }
    }

    private var nodePollKey: String { "\(site.id)-\(site.nodeEnabled)" }

    private var mainRow: some View {
        HStack(spacing: 11) {
            KTIconTile(tint: KTSiteVisuals.tint(for: site.type)) {
                KTSiteGlyph(kind: KTSiteVisuals.kind(for: site.type), size: 19,
                            color: KTSiteVisuals.tint(for: site.type).fg)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(site.name).font(KTType.rowName).foregroundStyle(KTColor.ink).lineLimit(1)
                TextField("domain", text: $domainDraft)
                    .textFieldStyle(.plain)
                    .font(.jbMono(12.5))
                    .foregroundStyle(domainError ? KTColor.danger : KTColor.muted)
                    .lineLimit(1)
                    .onSubmit(commitDomain)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)

            if site.type == .php {
                KTBadge(text: phpFramework.label, tint: KTSiteVisuals.tint(for: phpFramework), radius: 8)
                KTPhpMenu(current: site.phpVersion, versions: availableVersions, onSelect: onSetVersion)
            } else if site.type == .node {
                HStack(spacing: 8) {
                    KTBadge(text: site.type.label, tint: KTSiteVisuals.tint(for: site.type), radius: 8)
                    KTToggle(isOn: site.nodeEnabled, action: toggleNode)
                        .ktTip("Run this Node app and reverse-proxy the site to it")
                        .accessibilityLabel("Serve \(site.domain) with Node")
                }
            } else {
                KTBadge(text: site.type.label, tint: KTSiteVisuals.tint(for: site.type), radius: 8)
            }

            if site.type == .node {
                KTNodeStatusBadge(state: nodeState)
            } else {
                KTStatusLabel(running: canOpen).frame(width: 78, alignment: .leading)
            }

            KTToggle(isOn: site.secure, action: { onSetSecure(!site.secure) })
                .ktTip("Serve over HTTPS with a locally-trusted certificate")
                .accessibilityLabel("Serve \(site.domain) over HTTPS")

            KTSiteShareControls(shareStarting: shareStarting, shareURL: shareURL, onToggleShare: onToggleShare)

            KTButton(title: "Open", kind: .secondary, action: onOpen)
                .disabled(!canOpen)
                .ktTip("Open \(site.domain) in your browser")

            KTSiteActionsMenu(site: site, canOpen: canOpen,
                              onOpenLogs: onOpenLogs, onRemove: onRemove,
                              onRestore: onRestore, onError: onError)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
    }

    private func toggleNode() {
        server.toggleNode(site)
        Task { await refreshNodeState() }
    }

    private func saveNodeCommand() {
        let command = nodeCommandDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        server.setNodeCommand(site, command)
        Task { await refreshNodeState() }
    }

    private func installNodeDeps() {
        guard !nodeInstalling else { return }
        nodeInstalling = true
        Task {
            do { try await server.installNodeDeps(site) }
            catch { onError(error.localizedDescription) }
            nodeInstalling = false
            await refreshNodeState()
        }
    }

    private func pollNodeState() async {
        guard site.type == .node else { return }
        while !Task.isCancelled {
            await refreshNodeState()
            try? await Task.sleep(nanoseconds: 2_500_000_000)
        }
    }

    private func refreshNodeState() async {
        guard site.type == .node, site.nodeEnabled else { nodeState = .stopped; return }
        switch server.nodeReadiness(site) {
        case .needsRuntime: nodeState = .needsRuntime
        case .needsCommand: nodeState = .needsCommand
        case .needsInstall: nodeState = .needsInstall
        case .ready:        nodeState = await server.probeNode(site)
        }
    }

    private func detectFramework() async {
        guard site.type == .php else { return }
        phpFramework = await PHPFrameworkCache.shared.framework(path: site.path, docroot: site.docroot)
    }

    private func commitDomain() {
        let next = domainDraft.trimmingCharacters(in: .whitespaces).lowercased()
        guard next != site.domain else { domainError = false; return }
        do { try onEditDomain(next); domainError = false }
        catch {
            domainError = true
            domainDraft = site.domain
            onError(error.localizedDescription)
        }
    }
}
