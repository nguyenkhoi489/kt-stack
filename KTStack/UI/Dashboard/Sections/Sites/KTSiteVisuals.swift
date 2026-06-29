import AppKit
import KTStackKit
import SwiftUI

enum KTSiteVisuals {
    static func kind(for type: SiteType) -> KTSiteIconKind {
        switch type {
        case .php: .code
        case .node: .cube
        case .staticSite: .db
        }
    }

    static func tint(for type: SiteType) -> KTTint {
        switch type {
        case .php: KTIconTint.code
        case .node: KTIconTint.cube
        case .staticSite: KTIconTint.db
        }
    }

    static func tint(for framework: PHPFramework) -> KTTint {
        switch framework {
        case .wordpress: KTIconTint.wordpress
        case .laravel: KTIconTint.laravel
        case .plain: KTIconTint.php
        }
    }
}

enum KTSiteActions {
    static func revealInFinder(_ site: Site) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: site.path)])
    }

    static func openTerminal(_ site: Site) {
        let folder = URL(fileURLWithPath: site.path)
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(
            [folder],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    static func openInBrowser(_ site: Site) {
        let scheme = site.secure ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(site.domain)/") else { return }
        NSWorkspace.shared.open(url)
    }

    static func startNodeInTerminal(_ site: Site) {
        guard let port = site.nodePort else { return }
        let quotedDir = "'" + site.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let base = "cd \(quotedDir) && export PORT=\(port)"
        let shell: String
        if let command = resolvedStartCommand(site) {
            shell = base + " && " + command
        } else {
            let hint = "KTStack: PORT=\(port) set for \(site.domain). Run your dev server, e.g. npm run dev"
            shell = base + " && clear && echo \"\(hint)\""
        }
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = [
            "-e", "tell application \"Terminal\" to do script \"\(escaped)\"",
            "-e", "tell application \"Terminal\" to activate",
        ]
        try? proc.run()
    }

    private static func resolvedStartCommand(_ site: Site) -> String? {
        if let stored = site.nodeCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return stored
        }
        return SiteInspector().suggestedNodeCommand(at: URL(fileURLWithPath: site.path))
    }

    @discardableResult
    static func configureVSCode(_ site: Site) throws -> URL {
        let written = try IDEDebugConfigWriter().writeVSCode(
            projectRoot: URL(fileURLWithPath: site.path),
            docroot: URL(fileURLWithPath: site.docroot)
        )
        NSWorkspace.shared.activateFileViewerSelecting([written])
        return written
    }
}
