import KTStackKit
import SwiftUI

struct MenuBarVersionSwitcher: View {
    @EnvironmentObject private var runtimes: RuntimeManager

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space1) {
            Text("Default versions")
                .font(KDFont.footnote).foregroundStyle(.tertiary)
                .padding(.horizontal, KDSpacing.space1)
            switcherRow(.php)
            switcherRow(.node)
        }
    }

    private func switcherRow(_ lang: RuntimeLanguage) -> some View {
        let installed = runtimes.installed[lang] ?? []
        let current = runtimes.defaultVersion(lang)
        return HStack(spacing: KDSpacing.space2) {
            Image(systemName: lang.symbolName).frame(width: 18).foregroundStyle(.secondary)
            Text(lang.displayName).font(KDFont.body)
            Spacer()
            if installed.isEmpty {
                Text("none installed").font(KDFont.footnote).foregroundStyle(.tertiary)
            } else {
                Menu(current ?? "Select") {
                    ForEach(installed, id: \.self) { v in
                        Button { runtimes.setGlobalDefault(lang, v) } label: {
                            if v == current { Label(v, systemImage: "checkmark") } else { Text(v) }
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
        .padding(.vertical, KDSpacing.space1)
        .padding(.horizontal, KDSpacing.space1)
    }
}
