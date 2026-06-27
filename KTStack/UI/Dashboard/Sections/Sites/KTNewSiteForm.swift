import SwiftUI
import AppKit
import KTStackKit

struct KTNewSiteForm: View {
    @ObservedObject var registry: SiteRegistry
    let availableVersions: [String]
    let sitesRoot: URL
    let tld: String
    var defaultHTTPS = true
    let onClose: () -> Void

    @StateObject private var model = NewSiteModel()
    @State private var name = ""
    @State private var kind: NewSiteKind = .empty
    @State private var phpVersion = BundledPHP.defaultVersion
    @State private var adminPassword = KTNewSiteForm.randomPassword()
    @State private var advanced = false
    @State private var serveHTTPS = true
    @State private var createDatabase = false

    private var slug: String { SiteInspector.slug(name) }
    private var domain: String { "\(slug).\(tld)" }
    private var hasOverlay: Bool { model.installing || model.finished || model.error != nil }

    var body: some View {
        VStack(spacing: 0) {
            if hasOverlay {
                SiteInstallProgressView(events: model.events, error: model.error)
                    .padding(22)
                    .frame(maxHeight: 360)
            } else {
                ScrollView { form.padding(.horizontal, 24).padding(.vertical, 20) }
                    .frame(maxHeight: 460)
            }
            footer
        }
        .onAppear { serveHTTPS = defaultHTTPS }
        .onChange(of: kind) { newKind in createDatabase = newKind != .empty }
    }

    private var form: some View {
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
                formDropdown(width: 220,
                             options: NewSiteKind.allCases.map { k in
                                 KTDropdownOption(label: kindLabel(k), active: k == kind) { kind = k }
                             },
                             leading: { KTBadge(text: kindBadge(kind), tint: kindTint(kind)) },
                             value: kindLabel(kind))
            }
            row("PHP Version") {
                formDropdown(width: 150,
                             options: availableVersions.map { v in
                                 KTDropdownOption(label: "PHP \(v)", active: v == phpVersion) { phpVersion = v }
                             },
                             leading: { phpBadge },
                             value: "PHP \(phpVersion)")
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

            Rectangle().fill(Color(hex: 0xF0F0F3)).frame(height: 0.5)

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

    private var footer: some View {
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
                Text("Resolves at ")
                    .font(.jbMono(12.5)).foregroundColor(KTColor.muted)
                + Text(domain.isEmpty ? "" : domain)
                    .font(.jbMono(12.5, .regular)).foregroundColor(KTColor.accent)
                Spacer()
                KTButton(title: "Cancel", kind: .secondary) { onClose() }
                KTButton(title: "Create Site", systemImage: "plus", kind: .primary) { create() }
                    .disabled(slug.isEmpty || availableVersions.isEmpty)
            }
        }
        .padding(16)
        .padding(.horizontal, 8)
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0xF0F0F3)).frame(height: 0.5) }
    }

    private func create() {
        let request = NewSiteRequest(
            name: slug, kind: kind, phpVersion: phpVersion,
            folder: sitesRoot.appendingPathComponent(slug, isDirectory: true),
            domain: domain, databaseName: createDatabase ? slug : nil,
            siteTitle: slug, adminUser: "admin", adminEmail: "admin@example.com",
            adminPassword: kind == .wordpress ? adminPassword : "")
        model.install(request: request, registry: registry, openOnFinish: true, enableHTTPS: serveHTTPS)
    }

    // MARK helpers

    private func row<V: View>(_ label: String, topAligned: Bool = false, @ViewBuilder content: () -> V) -> some View {
        HStack(alignment: topAligned ? .top : .center, spacing: 16) {
            Text(label).font(.jbMono(14.5, .regular)).foregroundStyle(KTColor.ink)
                .frame(width: 138, alignment: .leading)
                .padding(.top, topAligned ? 10 : 0)
            content()
            Spacer(minLength: 0)
        }
    }

    private func fieldBox<V: View>(@ViewBuilder content: () -> V) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(KTColor.fieldBorderStrong, lineWidth: 1.5))
    }

    private func formDropdown<L: View>(width: CGFloat, options: [KTDropdownOption],
                                       @ViewBuilder leading: () -> L, value: String) -> some View {
        let lead = leading()
        return KTDropdown(width: width, options: options) {
            HStack(spacing: 11) {
                lead
                Text(value).font(.jbMono(14.5, .medium)).foregroundStyle(KTColor.ink)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(KTColor.muted)
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(KTColor.fieldBorderStrong, lineWidth: 1.5))
        }
    }

    private func smallTile<V: View>(_ tint: KTTint, @ViewBuilder content: () -> V) -> some View {
        content().foregroundStyle(tint.fg).frame(width: 27, height: 27)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.bg))
    }

    private var phpBadge: some View {
        Text("php").font(.jbMono(10, .bold)).foregroundStyle(.white)
            .padding(.vertical, 3).padding(.horizontal, 7)
            .background(Capsule().fill(Color(hex: 0x777BB3)))
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .regular)).foregroundStyle(KTColor.ink3)
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func helper(_ text: String) -> some View {
        Text(text).font(.jbMono(12.5)).foregroundStyle(KTColor.muted)
    }

    private func advancedToggle(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.jbMono(14, .regular)).foregroundStyle(KTColor.ink)
                Text(subtitle).font(.jbMono(12.5)).foregroundStyle(KTColor.muted)
            }
            Spacer()
            KTToggle(isOn: binding.wrappedValue) { binding.wrappedValue.toggle() }
        }
    }

    private func kindLabel(_ k: NewSiteKind) -> String {
        switch k {
        case .wordpress: return "WordPress"
        case .laravel: return "Laravel"
        case .empty: return "Empty Site"
        }
    }
    private func kindBadge(_ k: NewSiteKind) -> String {
        switch k {
        case .wordpress: return "WP"
        case .laravel: return "LV"
        case .empty: return "PHP"
        }
    }
    private func kindTint(_ k: NewSiteKind) -> KTTint {
        switch k {
        case .wordpress: return KTIconTint.code
        case .laravel: return KTTint(fg: Color(hex: 0xFF2D20), bg: Color(hex: 0xFFE9E7))
        case .empty: return KTIconTint.php
        }
    }

    static func randomPassword() -> String {
        let chars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<16).map { _ in chars.randomElement()! })
    }
}
