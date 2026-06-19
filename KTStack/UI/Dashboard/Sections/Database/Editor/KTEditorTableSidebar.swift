import SwiftUI
import KTStackKit

struct KTEditorTableSidebar: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    @Binding var filter: String
    var onRefresh: () -> Void
    var onAddTable: () -> Void

    private var filteredTables: [TableInfo] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return vm.tables }
        return vm.tables.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            tableList
        }
        .frame(width: 288)
        .background(Color(hex: 0xFBFBFC))
        .overlay(alignment: .trailing) { Rectangle().fill(KTColor.sep).frame(width: 0.5) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("TABLES")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(KTColor.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
            iconButton("arrow.clockwise", action: onRefresh)
            iconButton("plus", action: onAddTable)
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x86868F))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(KTColor.muted)
            TextField("Filter tables…", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(KTColor.ink)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color(hex: 0xE6E6EC), lineWidth: 0.5))
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var tableList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredTables) { table in
                    tableRow(table)
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 10)
        }
    }

    private func tableRow(_ table: TableInfo) -> some View {
        let active = vm.selectedTable?.name == table.name
        return Button { Task { await vm.select(table: table) } } label: {
            HStack(spacing: 9) {
                Image(systemName: table.isView ? "eye" : "tablecells")
                    .font(.system(size: 13))
                    .foregroundStyle(active ? KTColor.accent : KTColor.muted)
                Text(table.name)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? KTColor.accent : KTColor.ink2)
                    .lineLimit(1)
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
