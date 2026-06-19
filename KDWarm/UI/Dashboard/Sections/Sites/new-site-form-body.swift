import SwiftUI
import KDWarmKit

struct LabeledFormRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: KDSpacing.space3) {
            Text(label)
                .font(KDFont.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
                .padding(.top, 8)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NewSiteFormBody: View {
    let availableVersions: [String]
    let tld: String
    @Binding var name: String
    @Binding var kind: NewSiteKind
    @Binding var phpVersion: String
    @Binding var adminPassword: String
    @Binding var siteTitle: String
    @Binding var adminUser: String
    @Binding var adminEmail: String
    @Binding var advancedExpanded: Bool
    let regeneratePassword: () -> String

    private var slug: String { SiteInspector.slug(name) }
    private var domain: String { "\(slug).\(tld)" }

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space4) {
            siteNameRow
            typeRow
            phpRow
            if kind == .wordpress { adminPasswordRow }
            if !slug.isEmpty { domainRow }
            Divider().padding(.vertical, KDSpacing.space1)
            AdvancedOptionsDisclosure(expanded: $advancedExpanded) { advancedFields }
        }
    }

    private var siteNameRow: some View {
        LabeledFormRow(label: "Site Name") {
            VStack(alignment: .leading, spacing: KDSpacing.space1) {
                IconTextField(placeholder: "my-site", text: $name, font: KDFont.mono) {
                    FieldIconTile(systemName: "chevron.left.forward.chevron.right")
                }
                Text("This will be used as the folder name and site label.")
                    .font(KDFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var typeRow: some View {
        LabeledFormRow(label: "Type") {
            IconMenuField(title: kind.label,
                          icon: { FieldIconTile(systemName: kind == .wordpress ? "w.circle.fill" : "l.circle.fill") }) {
                ForEach(NewSiteKind.allCases) { item in
                    Button(item.label) { kind = item }
                }
            }
        }
    }

    private var phpRow: some View {
        LabeledFormRow(label: "PHP Version") {
            IconMenuField(title: phpVersion,
                          icon: { FieldIconTile(symbolText: "php") }) {
                ForEach(availableVersions, id: \.self) { version in
                    Button(version) { phpVersion = version }
                }
            }
        }
    }

    private var adminPasswordRow: some View {
        LabeledFormRow(label: "Admin Password") {
            VStack(alignment: .leading, spacing: KDSpacing.space1) {
                PasswordField(password: $adminPassword, onRegenerate: regeneratePassword)
                Text("This password will be used for the WordPress admin account.")
                    .font(KDFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var domainRow: some View {
        LabeledFormRow(label: "Domain") {
            Text("https://\(domain)")
                .font(KDFont.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            LabeledFormRow(label: "Site Title") {
                IconTextField(placeholder: slug.isEmpty ? "my-site" : slug, text: $siteTitle) {
                    FieldIconTile(systemName: "textformat")
                }
            }
            LabeledFormRow(label: "Admin User") {
                IconTextField(placeholder: "admin", text: $adminUser) {
                    FieldIconTile(systemName: "person.fill")
                }
            }
            LabeledFormRow(label: "Admin Email") {
                IconTextField(placeholder: "admin@example.com", text: $adminEmail) {
                    FieldIconTile(systemName: "envelope.fill")
                }
            }
        }
    }
}
