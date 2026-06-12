import SwiftUI
import AppKit
import KDWarmKit

/// "Add Site" sheet: choose a folder (defaults to the configured sites root), confirm the editable
/// domain (default `<dirname>.<tld>`, TLD-validated) and PHP version, then register it. Sites may live
/// anywhere — the managed root is only the picker's starting point, not a containment requirement.
struct AddSiteSheet: View {
    @ObservedObject var registry: SiteRegistry
    let availableVersions: [String]
    /// The managed sites root (`AppPreferences.sitesRootURL`) the folder picker opens at.
    let sitesRoot: URL
    @Environment(\.dismiss) private var dismiss

    @State private var folder: URL?
    @State private var domain = ""
    @State private var phpVersion = BundledPHP.defaultVersion
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Text("Add Site").font(KDFont.title)
            Text("Sites root: \(sitesRoot.path)")
                .font(KDFont.footnote).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)

            HStack {
                Text(folder?.path ?? "No folder selected")
                    .font(KDFont.mono).foregroundStyle(folder == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose Folder…", action: chooseFolder)
            }

            if folder != nil {
                Grid(alignment: .leading, verticalSpacing: KDSpacing.space2) {
                    GridRow {
                        Text("Domain").foregroundStyle(.secondary)
                        TextField("name.\(registry.tld)", text: $domain).font(KDFont.mono).frame(width: 240)
                    }
                    GridRow {
                        Text("PHP").foregroundStyle(.secondary)
                        Picker("", selection: $phpVersion) {
                            ForEach(availableVersions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(KDFont.footnote).foregroundStyle(Color.KDStatus.error)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Site", action: addSite)
                    .keyboardShortcut(.defaultAction)
                    .disabled(folder == nil || domain.isEmpty)
            }
        }
        .padding(KDSpacing.space4)
        .frame(width: 460)
    }

    private func chooseFolder() {
        // Create the managed root on first use so the picker actually opens there (NSOpenPanel falls
        // back to a default dir if directoryURL doesn't exist). Best-effort: 0700, owner-only.
        try? FileManager.default.createDirectory(at: sitesRoot, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = sitesRoot
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            folder = url
            domain = "\(SiteInspector.slug(url.lastPathComponent)).\(registry.tld)"
            error = nil
        }
    }

    private func addSite() {
        guard let folder else { return }
        let wanted = domain.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            try registry.validateDomain(wanted)           // fail fast before registering
            let site = try registry.add(folder: folder, phpVersion: phpVersion)
            if site.domain != wanted { try registry.editDomain(site, to: wanted) }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
