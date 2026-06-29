import KTStackKit
import SwiftUI

struct ConnectionSidebarView: View {
    @EnvironmentObject private var store: ConnectionStore
    @EnvironmentObject private var vm: DatabaseViewModel
    @EnvironmentObject private var documentVM: DocumentViewModel
    @State private var sheet: SheetMode?

    enum SheetMode: Identifiable {
        case add
        case edit(ConnectionProfile)
        var id: String {
            switch self {
            case .add: "add"
            case let .edit(profile): profile.id.uuidString
            }
        }

        /// The profile to prefill, or nil when adding.
        var editingProfile: ConnectionProfile? {
            if case let .edit(profile) = self { return profile }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: KDSpacing.space2) {
                Text("Connections")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { sheet = .add } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Add a connection")
            }
            .padding(.horizontal, KDSpacing.space3)
            .padding(.vertical, KDSpacing.space2)
            Divider()
            List {
                ForEach(store.allProfiles) { profile in
                    row(profile)
                        .contentShape(Rectangle())
                        .onTapGesture { Task { await select(profile) } }
                        .contextMenu { rowMenu(profile) }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 180, idealWidth: 200)
        .sheet(item: $sheet) { mode in
            AddConnectionSheet(editing: mode.editingProfile)
                .environmentObject(store)
        }
    }

    private func select(_ profile: ConnectionProfile) async {
        if profile.kind == .mongodb {
            vm.deselect()
            await documentVM.select(profile: profile)
        } else {
            documentVM.deselect()
            await vm.select(profile: profile)
        }
    }

    @ViewBuilder
    private func rowMenu(_ profile: ConnectionProfile) -> some View {
        if !profile.isManaged {
            Button("Edit…") { sheet = .edit(profile) }
            Button("Delete", role: .destructive) { store.remove(profile) }
        }
    }

    @ViewBuilder
    private func row(_ profile: ConnectionProfile) -> some View {
        let isSelected = selectedProfileID == profile.id
        HStack(spacing: KDSpacing.space2) {
            Image(systemName: icon(for: profile.kind))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name).font(KDFont.body)
                Text(profile.isManaged ? "managed · loopback" : "\(profile.host):\(profile.port)")
                    .font(KDFont.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isSelected { stateIcon(for: profile) }
        }
        .padding(.vertical, KDSpacing.space1)
    }

    private var selectedProfileID: ConnectionProfile.ID? {
        vm.selectedProfile?.id ?? documentVM.selectedProfile?.id
    }

    private func icon(for kind: DatabaseKind) -> String {
        switch kind {
        case .mysql: "cylinder.split.1x2"
        case .mongodb: "doc.text"
        case .postgres, .sqlite: "cylinder"
        }
    }

    @ViewBuilder
    private func stateIcon(for profile: ConnectionProfile) -> some View {
        if profile.kind == .mongodb {
            stateIcon(
                connecting: documentVM.connection == .connecting,
                connected: documentVM.connection == .connected,
                failed: isFailed(documentVM.connection)
            )
        } else {
            stateIcon(
                connecting: vm.connection == .connecting,
                connected: vm.connection == .connected,
                failed: isFailed(vm.connection)
            )
        }
    }

    @ViewBuilder
    private func stateIcon(connecting: Bool, connected: Bool, failed: Bool) -> some View {
        if connecting {
            ProgressView().controlSize(.small)
        } else if connected {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if failed {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private func isFailed(_ connection: DatabaseViewModel.Connection) -> Bool {
        if case .failed = connection { return true }
        return false
    }

    private func isFailed(_ connection: DocumentViewModel.Connection) -> Bool {
        if case .failed = connection { return true }
        return false
    }
}
