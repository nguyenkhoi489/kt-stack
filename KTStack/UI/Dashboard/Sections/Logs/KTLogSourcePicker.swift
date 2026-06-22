import SwiftUI
import KTStackKit

struct KTLogSourcePicker: View {
    let sources: [LogSource]
    @Binding var selectedID: String?
    let onClose: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [LogSource] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sources }
        return sources.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KTColor.sep).frame(height: 0.5)
            searchField
            Rectangle().fill(KTColor.sep).frame(height: 0.5)
            list
        }
        .frame(width: 440, height: 520)
        .background(Color.white)
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.alignleft").font(.system(size: 13, weight: .medium)).foregroundStyle(KTColor.muted)
            Text("Log source").font(.jbMono(15, .bold)).foregroundStyle(KTColor.ink)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KTColor.muted).frame(width: 26, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(KTColor.muted)
            TextField("Filter sources…", text: $query)
                .textFieldStyle(.plain)
                .font(.jbMono(13))
                .foregroundStyle(KTColor.ink)
                .focused($searchFocused)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(filtered) { source in
                    row(source)
                }
                if filtered.isEmpty {
                    Text("No matching source").font(.jbMono(12)).foregroundStyle(KTColor.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ source: LogSource) -> some View {
        let active = source.id == selectedID
        return Button {
            selectedID = source.id
            onClose()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(KTColor.accent).opacity(active ? 1 : 0).frame(width: 12)
                Text(source.displayName).font(.jbMono(12.5)).foregroundStyle(KTColor.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(active ? KTColor.accentSoft : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
