import SwiftUI
import KDWarmKit

/// "Install Version…" sheet (design §5.8): pick a downloadable runtime release and install it with
/// determinate progress + cancel. Reuses `RuntimeManager` state, so a download started here shows the
/// same progress on the matching Bento card.
struct RuntimeDownloadSheet: View {
    @EnvironmentObject private var runtimes: RuntimeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Text("Install a runtime").font(KDFont.title)
            Text("Official builds are verified by SHA-256 before install.")
                .font(KDFont.footnote).foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: KDSpacing.space2) {
                    ForEach(languagesWithReleases, id: \.self) { lang in
                        languageGroup(lang)
                    }
                    if languagesWithReleases.isEmpty {
                        Text("Everything in the catalog is already installed.")
                            .font(KDFont.footnote).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(minHeight: 180)

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(KDSpacing.space4)
        .frame(width: 420)
    }

    private var languagesWithReleases: [RuntimeLanguage] {
        RuntimeLanguage.allCases.filter { !runtimes.availableReleases($0).isEmpty || runtimes.downloads[$0] != nil }
    }

    private func languageGroup(_ lang: RuntimeLanguage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lang.displayName).font(KDFont.footnote).foregroundStyle(.secondary)
            if let dl = runtimes.downloads[lang], dl.error == nil {
                HStack {
                    ProgressView(value: dl.fraction).frame(maxWidth: 200)
                    Text("\(Int(dl.fraction * 100))%").font(KDFont.footnote).foregroundStyle(.tertiary)
                    Spacer()
                    Button("Cancel") { runtimes.cancel(lang) }.buttonStyle(.link)
                }
            }
            ForEach(runtimes.availableReleases(lang)) { release in
                HStack {
                    Image(systemName: lang.symbolName).foregroundStyle(.secondary).frame(width: 20)
                    Text(release.version).font(KDFont.mono)
                    Spacer()
                    Button("Install") { runtimes.install(release) }
                        .disabled(runtimes.isDownloading(lang))
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
