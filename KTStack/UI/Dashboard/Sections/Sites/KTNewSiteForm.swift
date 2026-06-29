import AppKit
import KTStackKit
import SwiftUI

enum NewSiteMode: Hashable { case create, importFolder }

struct KTNewSiteForm: View {
    @ObservedObject var registry: SiteRegistry
    let availableVersions: [String]
    let sitesRoot: URL
    let tld: String
    var defaultHTTPS = true
    let onClose: () -> Void

    @StateObject private var model = NewSiteModel()
    @State private var mode: NewSiteMode = .create
    @State private var name = ""
    @State private var kind: NewSiteKind = .empty
    @State private var phpVersion = BundledPHP.defaultVersion
    @State private var adminPassword = KTNewSiteForm.randomPassword()
    @State private var advanced = false
    @State private var serveHTTPS = true
    @State private var createDatabase = false
    @State private var importFolder: URL?
    @State private var importName = ""

    private var slug: String {
        SiteInspector.slug(name)
    }

    private var domain: String {
        "\(slug).\(tld)"
    }

    private var importSlug: String {
        SiteInspector.slug(importName)
    }

    private var importDomain: String {
        "\(importSlug).\(tld)"
    }

    private var hasOverlay: Bool {
        model.installing || model.finished || model.error != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hasOverlay { modeSwitcher }
            if hasOverlay {
                SiteInstallProgressView(events: model.events, error: model.error)
                    .padding(22)
                    .frame(maxHeight: 360)
            } else {
                ScrollView { activeForm.padding(.horizontal, 24).padding(.vertical, 18) }
                    .frame(maxHeight: 440)
            }
            footer
        }
        .onAppear { serveHTTPS = defaultHTTPS }
        .onChange(of: kind) { newKind in createDatabase = newKind != .empty }
    }

    private var modeSwitcher: some View {
        HStack {
            KTSegmentedTabs(items: [
                KTSegmentedTabs.Item(value: .create, label: "Create New"),
                KTSegmentedTabs.Item(value: .importFolder, label: "Import Folder"),
            ], selection: $mode, large: true)
            Spacer()
        }
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 2)
    }

    @ViewBuilder
    private var activeForm: some View {
        switch mode {
        case .create:
            createForm
        case .importFolder:
            KTImportFolderForm(
                folder: $importFolder,
                name: $importName,
                phpVersion: $phpVersion,
                serveHTTPS: $serveHTTPS,
                createDatabase: $createDatabase,
                availableVersions: availableVersions
            )
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            row("Site Name", topAligned: true) {
                VStack(alignment: .leading, spacing: 7) {
                    fieldBox {
                        smallTile(KTIconTint.code) { KTSiteGlyph(kind: .code, size: 15, color: KTIconTint.code.fg) }
                        TextField("my-site", text: $name).textFieldStyle(.plain).font(.jbMono(14.5)).foregroundStyle(KTColor.ink)
                    }
                    helper("This will be used as the folder name and site label.")
                }
            }
            row("Type") {
                formDropdown(
                    width: 220,
                    options: NewSiteKind.allCases.map { k in
                        KTDropdownOption(label: kindLabel(k), active: k == kind) { kind = k }
                    },
                    leading: { KTBadge(text: kindBadge(kind), tint: kindTint(kind)) },
                    value: kindLabel(kind)
                )
            }
            row("PHP Version") {
                formDropdown(
                    width: 150,
                    options: availableVersions.map { v in
                        KTDropdownOption(label: "PHP \(v)", active: v == phpVersion) { phpVersion = v }
                    },
                    leading: { phpBadge },
                    value: "PHP \(phpVersion)"
                )
            }
            if kind != .empty {
                row("Admin Password", topAligned: true) {
                    VStack(alignment: .leading, spacing: 7) {
                        fieldBox {
                            Image(systemName: "lock").font(.system(size: 14, weight: .regular)).foregroundStyle(KTColor.muted)
                            Text(adminPassword).font(.jbMono(14)).foregroundStyle(KTColor.ink)
                            Spacer(minLength: 0)
                            iconButton("arrow.clockwise") { adminPassword = KTNewSiteForm.randomPassword() }
                            iconButton("doc.on.doc") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(adminPassword, forType: .string)
                            }
                        }
                        helper("This password will be used for the \(kindLabel(kind)) admin account.")
                    }
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
                    advancedToggle("Serve over HTTPS", "Issue a trusted local certificate.", $serveHTTPS)
                    advancedToggle("Create database", "Provision a matching MySQL database.", $createDatabase)
                }
                .padding(.leading, 29)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if mode == .importFolder { importFooter } else { createFooter }
    }

    private var createFooter: some View {
        HStack(spacing: 10) {
            if model.finished {
                Spacer()
                KTButton(title: "Done", kind: .primary) { onClose() }
            } else if model.installing {
                Spacer()
                KTButton(title: "Cancel", kind: .secondary) { model.cancel() }
            } else if model.error != nil {
                Spacer()
                KTButton(title: "Back", kind: .secondary) { model.reset() }
                KTButton(title: "Try Again", kind: .primary) { create() }
            } else {
                resolvesLabel(domain)
                Spacer()
                KTButton(title: "Cancel", kind: .secondary) { onClose() }
                KTButton(title: "Create Site", systemImage: "plus", kind: .primary) { create() }
                    .disabled(slug.isEmpty || availableVersions.isEmpty)
            }
        }
        .padding(16)
        .padding(.horizontal, 8)
        .overlay(alignment: .top) { KTSiteFormControls.hairline }
    }

    private var importFooter: some View {
        HStack(spacing: 10) {
            if model.finished {
                Spacer()
                KTButton(title: "Done", kind: .primary) { onClose() }
            } else if model.installing {
                Spacer()
                KTButton(title: "Cancel", kind: .secondary) { model.cancel() }
            } else if model.error != nil {
                Spacer()
                KTButton(title: "Back", kind: .secondary) { model.reset() }
                KTButton(title: "Try Again", kind: .primary) { importSite() }
            } else {
                resolvesLabel(importDomain)
                Spacer()
                KTButton(title: "Cancel", kind: .secondary) { onClose() }
                KTButton(title: "Import Site", systemImage: "square.and.arrow.down", kind: .primary) { importSite() }
                    .disabled(importFolder == nil || importSlug.isEmpty || availableVersions.isEmpty)
            }
        }
        .padding(16)
        .padding(.horizontal, 8)
        .overlay(alignment: .top) { KTSiteFormControls.hairline }
    }

    private func resolvesLabel(_ value: String) -> some View {
        Text("Resolves at ")
            .font(.jbMono(12.5)).foregroundColor(KTColor.muted)
            + Text(value.isEmpty ? "" : value)
            .font(.jbMono(12.5, .regular)).foregroundColor(KTColor.accent)
    }

    private func create() {
        let request = NewSiteRequest(
            name: slug, kind: kind, phpVersion: phpVersion,
            folder: sitesRoot.appendingPathComponent(slug, isDirectory: true),
            domain: domain, databaseName: createDatabase ? slug : nil,
            siteTitle: slug, adminUser: "admin", adminEmail: "admin@example.com",
            adminPassword: kind == .wordpress ? adminPassword : ""
        )
        model.install(request: request, registry: registry, openOnFinish: true, enableHTTPS: serveHTTPS)
    }

    private func importSite() {
        guard let importFolder else { return }
        model.importExisting(
            folder: importFolder,
            domain: importDomain,
            phpVersion: phpVersion,
            createDatabase: createDatabase,
            enableHTTPS: serveHTTPS,
            registry: registry,
            openOnFinish: true
        )
    }

    private func row(_ label: String, topAligned: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        KTSiteFormControls.row(label, topAligned: topAligned, content: content)
    }

    private func fieldBox(@ViewBuilder content: () -> some View) -> some View {
        KTSiteFormControls.fieldBox(content: content)
    }

    private func formDropdown(
        width: CGFloat,
        options: [KTDropdownOption],
        @ViewBuilder leading: () -> some View,
        value: String
    ) -> some View {
        KTSiteFormControls.formDropdown(width: width, options: options, leading: leading, value: value)
    }

    private func smallTile(_ tint: KTTint, @ViewBuilder content: () -> some View) -> some View {
        KTSiteFormControls.smallTile(tint, content: content)
    }

    private var phpBadge: some View {
        KTSiteFormControls.phpBadge
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        KTSiteFormControls.iconButton(symbol, action: action)
    }

    private func helper(_ text: String) -> some View {
        KTSiteFormControls.helper(text)
    }

    private func advancedToggle(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        KTSiteFormControls.advancedToggle(title, subtitle, binding)
    }

    private func kindLabel(_ k: NewSiteKind) -> String {
        switch k {
        case .wordpress: "WordPress"
        case .laravel: "Laravel"
        case .empty: "Empty Site"
        }
    }

    private func kindBadge(_ k: NewSiteKind) -> String {
        switch k {
        case .wordpress: "WP"
        case .laravel: "LV"
        case .empty: "PHP"
        }
    }

    private func kindTint(_ k: NewSiteKind) -> KTTint {
        switch k {
        case .wordpress: KTIconTint.code
        case .laravel: KTTint(fg: Color(hex: 0xFF2D20), bg: Color(hex: 0xFFE9E7))
        case .empty: KTIconTint.php
        }
    }

    static func randomPassword() -> String {
        let chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<16).map { _ in chars.randomElement()! })
    }
}
