import SwiftUI
import AppKit
import KDWarmKit

struct AddSiteSheet: View {
    @ObservedObject var registry: SiteRegistry
    let availableVersions: [String]

    let sitesRoot: URL
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case create = "Create Folder"
        case existing = "Choose Folder"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .create
    @State private var name = ""
    @State private var folder: URL?
    @State private var domain = ""
    @State private var phpVersion = BundledPHP.defaultVersion
    @State private var error: String?

    private var slug: String { SiteInspector.slug(name) }
    private var hasCreateName: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var createdFolder: URL {
        sitesRoot.appendingPathComponent(slug, isDirectory: true)
    }

    private var targetFolder: URL? {
        switch mode {
        case .create:   return hasCreateName ? createdFolder : nil
        case .existing: return folder
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Text("Add Site").font(KDFont.title)
            Text("Sites root: \(sitesRoot.path)")
                .font(KDFont.footnote).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { _ in error = nil }

            switch mode {
            case .create:
                createFields
            case .existing:
                existingFolderPicker
                if folder != nil { settingsGrid }
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
                    .disabled(!canSubmit)
            }
        }
        .padding(KDSpacing.space4)
        .frame(width: 460)
    }

    private var createFields: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space2) {
            Grid(alignment: .leading, verticalSpacing: KDSpacing.space2) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("my-site", text: $name)
                        .font(KDFont.mono)
                        .frame(width: 240)
                        .onChange(of: name) { _ in updateCreateDomain() }
                }
                GridRow {
                    Text("Folder").foregroundStyle(.secondary)
                    Text(hasCreateName ? createdFolder.path : sitesRoot.appendingPathComponent("my-site").path)
                        .font(KDFont.mono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            settingsGrid
        }
    }

    private var existingFolderPicker: some View {
        HStack {
            Text(folder?.path ?? "No folder selected")
                .font(KDFont.mono).foregroundStyle(folder == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Choose Folder…", action: chooseFolder)
        }
    }

    private var settingsGrid: some View {
        Grid(alignment: .leading, verticalSpacing: KDSpacing.space2) {
            GridRow {
                Text("Domain").foregroundStyle(.secondary)
                TextField("name.\(registry.tld)", text: $domain)
                    .font(KDFont.mono)
                    .frame(width: 240)
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

    private var canSubmit: Bool {
        targetFolder != nil && !domain.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func chooseFolder() {

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

    private func updateCreateDomain() {
        domain = "\(slug).\(registry.tld)"
        error = nil
    }

    private func addSite() {
        guard let folder = targetFolder else { return }
        let wanted = domain.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            try registry.validateDomain(wanted)
            if mode == .create {
                try FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
            }
            let site = try registry.add(folder: folder, phpVersion: phpVersion)
            if site.domain != wanted { try registry.editDomain(site, to: wanted) }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
