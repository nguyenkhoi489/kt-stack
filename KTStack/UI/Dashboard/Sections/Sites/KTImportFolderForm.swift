import AppKit
import KTStackKit
import SwiftUI

struct KTImportFolderForm: View {
    @Binding var folder: URL?
    @Binding var name: String
    @Binding var phpVersion: String
    @Binding var serveHTTPS: Bool
    @Binding var createDatabase: Bool
    let availableVersions: [String]
    @State private var advanced = false
    @State private var detectedType: SiteType?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            KTSiteFormControls.row("Folder", topAligned: true) {
                VStack(alignment: .leading, spacing: 7) {
                    KTSiteFormControls.fieldBox {
                        KTSiteFormControls.smallTile(KTIconTint.cube) {
                            Image(systemName: "folder").font(.system(size: 14, weight: .regular))
                        }
                        Text(folder?.path ?? "No folder selected")
                            .font(.jbMono(13.5)).foregroundStyle(folder == nil ? KTColor.muted : KTColor.ink)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        KTButton(title: "Choose…", kind: .secondary) { pickFolder() }
                    }
                    KTSiteFormControls.helper("KTStack serves this folder in place — files are never moved or copied.")
                }
            }

            KTSiteFormControls.row("Domain", topAligned: true) {
                VStack(alignment: .leading, spacing: 7) {
                    KTSiteFormControls.fieldBox {
                        KTSiteFormControls.smallTile(KTIconTint.code) {
                            KTSiteGlyph(kind: .code, size: 15, color: KTIconTint.code.fg)
                        }
                        TextField("my-site", text: $name).textFieldStyle(.plain)
                            .font(.jbMono(14.5)).foregroundStyle(KTColor.ink)
                    }
                    KTSiteFormControls.helper("The subdomain used to serve this site.")
                }
            }

            KTSiteFormControls.row("PHP Version") {
                KTSiteFormControls.formDropdown(
                    width: 150,
                    options: availableVersions.map { v in
                        KTDropdownOption(label: "PHP \(v)", active: v == phpVersion) { phpVersion = v }
                    },
                    leading: { KTSiteFormControls.phpBadge },
                    value: "PHP \(phpVersion)"
                )
            }

            if let detectedType {
                KTSiteFormControls.row("Detected") {
                    HStack(spacing: 9) {
                        Image(systemName: detectedType.symbolName)
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(KTColor.ink3)
                        Text(detectedType.label).font(.jbMono(14, .regular)).foregroundStyle(KTColor.ink)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 12)
                    .background(Capsule().fill(KTColor.segmentBg))
                }
            }

            KTSiteFormControls.hairline

            Button { withAnimation(.easeInOut(duration: 0.15)) { advanced.toggle() } } label: {
                HStack(spacing: 11) {
                    Image(systemName: "gearshape").font(.system(size: 15, weight: .regular)).foregroundStyle(KTColor.ink3)
                    Text("Advanced Options").font(KTType.label).foregroundStyle(KTColor.ink)
                    Spacer()
                    Image(systemName: advanced ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(KTColor.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if advanced {
                VStack(spacing: 14) {
                    KTSiteFormControls.advancedToggle("Serve over HTTPS", "Issue a trusted local certificate.", $serveHTTPS)
                    KTSiteFormControls.advancedToggle("Create database", "Provision a matching MySQL database.", $createDatabase)
                }
                .padding(.leading, 29)
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select a project folder to serve locally."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        detectedType = SiteInspector().inspect(folder: url).type
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = url.lastPathComponent
        }
    }
}
