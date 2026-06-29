import AppKit
import KTStackKit
import SwiftUI

struct KTSiteListRow: View {
    let site: Site
    let availableVersions: [String]
    let canOpen: Bool
    let isSharing: Bool
    var shareStarting: Bool = false
    var shareURL: URL?
    var shareExpiresAt: Date?
    let onOpen: () -> Void
    let onSetVersion: (String) -> Void
    let onSetSecure: (Bool) -> Void
    let onEditDomain: (String) throws -> Void
    let onOpenLogs: () -> Void
    let onToggleShare: (Bool) -> Void
    let onRemove: () -> Void
    var onError: (String) -> Void = { _ in }
    var onRestore: () -> Void = {}

    @EnvironmentObject private var server: LocalServerController
    @State private var domainDraft: String
    @State private var domainError = false
    @State private var hovering = false
    @State private var nodeState: NodeSiteController.State = .stopped
    @State private var nodePortDraft: String
    @State private var phpFramework: PHPFramework = .plain

    init(
        site: Site,
        availableVersions: [String],
        canOpen: Bool,
        isSharing: Bool,
        shareStarting: Bool = false,
        shareURL: URL? = nil,
        shareExpiresAt: Date? = nil,
        onOpen: @escaping () -> Void,
        onSetVersion: @escaping (String) -> Void,
        onSetSecure: @escaping (Bool) -> Void,
        onEditDomain: @escaping (String) throws -> Void,
        onOpenLogs: @escaping () -> Void,
        onToggleShare: @escaping (Bool) -> Void,
        onRemove: @escaping () -> Void,
        onError: @escaping (String) -> Void = { _ in },
        onRestore: @escaping () -> Void = {}
    ) {
        self.site = site
        self.availableVersions = availableVersions
        self.canOpen = canOpen
        self.isSharing = isSharing
        self.shareStarting = shareStarting
        self.shareURL = shareURL
        self.shareExpiresAt = shareExpiresAt
        self.onOpen = onOpen
        self.onSetVersion = onSetVersion
        self.onSetSecure = onSetSecure
        self.onEditDomain = onEditDomain
        self.onOpenLogs = onOpenLogs
        self.onToggleShare = onToggleShare
        self.onRemove = onRemove
        self.onError = onError
        self.onRestore = onRestore
        _domainDraft = State(initialValue: site.domain)
        _nodePortDraft = State(initialValue: site.nodePort.map(String.init) ?? "")
    }

    var body: some View {
        mainRow
            .background(hovering ? KTColor.rowHover : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .task(id: nodePollKey) { await pollNodeState() }
            .task(id: site.path) { await detectFramework() }
            .onChange(of: site.domain) { new in domainDraft = new; domainError = false }
            .onChange(of: site.nodePort) { new in nodePortDraft = new.map(String.init) ?? "" }
    }

    private var nodePollKey: String {
        "\(site.id)-\(site.nodePort ?? 0)"
    }

    private var mainRow: some View {
        HStack(spacing: 11) {
            KTIconTile(tint: KTSiteVisuals.tint(for: site.type)) {
                KTSiteGlyph(
                    kind: KTSiteVisuals.kind(for: site.type),
                    size: 19,
                    color: KTSiteVisuals.tint(for: site.type).fg
                )
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
                    nodeRoute
                }
            } else {
                KTBadge(text: site.type.label, tint: KTSiteVisuals.tint(for: site.type), radius: 8)
            }

            if site.type == .node {
                nodeStatusControl
            } else {
                KTStatusLabel(running: canOpen).frame(width: 78, alignment: .leading)
            }

            KTToggle(isOn: site.secure, action: { onSetSecure(!site.secure) })
                .ktTip("Serve over HTTPS with a locally-trusted certificate")
                .accessibilityLabel("Serve \(site.domain) over HTTPS")

            KTSiteShareControls(
                shareStarting: shareStarting,
                shareURL: shareURL,
                shareExpiresAt: shareExpiresAt,
                onToggleShare: onToggleShare
            )

            KTButton(title: "Open", kind: .secondary, action: onOpen)
                .disabled(!openEnabled)
                .ktTip("Open \(site.domain) in your browser")

            KTSiteActionsMenu(
                site: site,
                canOpen: canOpen,
                onOpenLogs: onOpenLogs,
                onRemove: onRemove,
                onRestore: onRestore,
                onError: onError
            )
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
    }

    private var openEnabled: Bool {
        site.type == .node ? (canOpen && nodeState == .running) : canOpen
    }

    private var nodeRoute: some View {
        HStack(spacing: 4) {
            Text("→ localhost:").font(.jbMono(12.5)).foregroundStyle(KTColor.faint)
            nodePortField
        }
    }

    @ViewBuilder
    private var nodeStatusControl: some View {
        Group {
            if nodeState == .running {
                KTOnlineLabel(text: "live")
            } else if site.nodePort != nil {
                KTButton(title: "Start", kind: .secondary) { KTSiteActions.startNodeInTerminal(site) }
                    .ktTip("Open Terminal at the project with PORT set; run your dev server there")
            } else {
                Text("set a port").font(.jbMono(12)).foregroundStyle(KTColor.faint)
            }
        }
        .frame(width: 104, alignment: .leading)
    }

    private var nodePortField: some View {
        TextField("port", text: $nodePortDraft)
            .textFieldStyle(.plain)
            .font(.jbMono(12.5))
            .foregroundStyle(KTColor.ink)
            .frame(width: 46)
            .multilineTextAlignment(.center)
            .padding(.vertical, 2).padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(KTColor.pillBg))
            .onSubmit(saveNodePort)
            .ktTip("Port your Node app listens on; KTStack proxies this site to it")
            .accessibilityLabel("Node port for \(site.domain)")
    }

    private func saveNodePort() {
        let trimmed = nodePortDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            server.setNodePort(site, nil)
            return
        }
        guard let port = Int(trimmed), (1 ... 65535).contains(port) else {
            nodePortDraft = site.nodePort.map(String.init) ?? ""
            onError("Enter a port between 1 and 65535.")
            return
        }
        if let other = server.registry.sites.first(where: { $0.id != site.id && $0.nodePort == port }) {
            nodePortDraft = site.nodePort.map(String.init) ?? ""
            onError("Port \(port) is already used by \(other.domain). Each Node site needs its own port.")
            return
        }
        server.setNodePort(site, port)
    }

    private func pollNodeState() async {
        guard site.type == .node else { return }
        while !Task.isCancelled {
            await refreshNodeState()
            try? await Task.sleep(nanoseconds: 2_500_000_000)
        }
    }

    private func refreshNodeState() async {
        guard site.type == .node else { nodeState = .stopped; return }
        nodeState = await server.probeNode(site)
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
