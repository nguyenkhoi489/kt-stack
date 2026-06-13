import SwiftUI
import KDWarmKit

/// About tab (Settings §): app identity + author credit. Read-only; the author link opens in the
/// default browser. Version is read from the bundle so it tracks the build, not a hardcoded string.
struct AboutSettingsView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: KDSpacing.space3) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 40)).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("KDWarm").font(KDFont.title)
                        Text("Local web development host manager for macOS")
                            .font(KDFont.footnote).foregroundStyle(.secondary)
                        Text("Version \(version)").font(KDFont.footnote).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, KDSpacing.space1)
            }

            Section("Author") {
                LabeledContent("Tác giả", value: "Nguyên Khôi")
                HStack {
                    Text("Website")
                    Spacer()
                    Link("nguyenkhoi.dev", destination: URL(string: "https://nguyenkhoi.dev")!)
                        .font(KDFont.body)
                }
            }

            Section {
                Text("© 2026 Nguyên Khôi · nguyenkhoi.dev")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(KDSpacing.space4)
    }
}
