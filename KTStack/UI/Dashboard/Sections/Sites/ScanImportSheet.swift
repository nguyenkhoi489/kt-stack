import KTStackKit
import SwiftUI

struct ScanImportSheet: View {
    @ObservedObject var registry: SiteRegistry
    let sitesRoot: URL
    @Environment(\.dismiss) private var dismiss

    @State private var scanned: [SiteScanner.ScannedSite] = []
    @State private var selected: Set<String> = [] // folder.path of ticked rows
    @State private var didScan = false

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Text("Scan & Import Sites").font(KDFont.title)
            Text("Folders in \(sitesRoot.path)")
                .font(KDFont.footnote).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)

            content

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(importTitle, action: importSelected)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
        }
        .padding(KDSpacing.space4)
        .frame(width: 520)
        .task { await runScan() }
    }

    @ViewBuilder
    private var content: some View {
        if scanned.isEmpty {
            Text(didScan ? "No importable folders found in this root." : "Scanning…")
                .font(KDFont.body).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(scanned) { row in
                        rowView(row)
                        Divider()
                    }
                }
            }
            .frame(height: 280)
        }
    }

    private var importTitle: String {
        selected.isEmpty ? "Import" : "Import \(selected.count) Site\(selected.count == 1 ? "" : "s")"
    }

    private func rowView(_ row: SiteScanner.ScannedSite) -> some View {
        HStack(spacing: KDSpacing.space2) {
            Toggle("", isOn: binding(for: row)).labelsHidden().disabled(row.alreadyRegistered)
            Image(systemName: row.type.symbolName).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.folder.lastPathComponent).font(KDFont.body)
                Text(row.proposedDomain).font(KDFont.mono).foregroundStyle(.secondary)
            }
            Spacer()
            Text(row.alreadyRegistered ? "Added" : row.type.label)
                .font(KDFont.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, KDSpacing.space2)
        .opacity(row.alreadyRegistered ? 0.55 : 1)
    }

    private func binding(for row: SiteScanner.ScannedSite) -> Binding<Bool> {
        Binding(
            get: { selected.contains(row.folder.path) },
            set: { on in
                if on { selected.insert(row.folder.path) } else { selected.remove(row.folder.path) }
            }
        )
    }

    private func runScan() async {
        let root = sitesRoot, tld = registry.tld, existing = registry.sites.map(\.path)
        let result = await Task.detached {
            SiteScanner().scan(root: root, tld: tld, existingPaths: existing)
        }.value
        scanned = result
        selected = Set(result.filter { !$0.alreadyRegistered }.map(\.folder.path))
        didScan = true
    }

    private func importSelected() {
        for row in scanned where selected.contains(row.folder.path) && !row.alreadyRegistered {
            do {
                try registry.add(folder: row.folder)
            } catch {
                NSLog("KTStack: scan import skipped \(row.folder.lastPathComponent): \(error.localizedDescription)")
            }
        }
        dismiss()
    }
}
