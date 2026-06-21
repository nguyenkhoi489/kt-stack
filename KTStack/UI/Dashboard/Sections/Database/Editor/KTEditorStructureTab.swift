import SwiftUI
import KTStackKit

struct KTEditorStructureTab: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    let isActive: Bool

    @State private var selectedColumn: String?
    @State private var ddlSheet: DDLActionSheet.Mode?

    private let columns = ["Column", "Type", "Null", "Key", "Default"]
    private let weights: [CGFloat] = [1.4, 1.2, 0.6, 0.7, 1.1]

    var body: some View {
        VStack(spacing: 0) {
            if !vm.isReadOnlyConnection { ddlToolbar }
            Group {
                if vm.selectedTable == nil {
                    placeholder("Select a table to view its structure.")
                } else if vm.currentColumns.isEmpty {
                    placeholder("No columns found for this table.")
                } else {
                    GeometryReader { geo in
                        let widths = columnWidths(total: geo.size.width)
                        ScrollView {
                            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                                Section { rows(widths) } header: { headerRow(widths) }
                            }
                            if !vm.currentIndexes.isEmpty { indexesSection }
                        }
                    }
                }
            }
        }
        .task(id: EditorTabTaskKey(value: vm.selectedTable, isActive: isActive)) {
            guard isActive else { return }
            await vm.loadStructure()
        }
        .onChange(of: vm.selectedTable) { _ in selectedColumn = nil }
        .sheet(item: $ddlSheet) { DDLActionSheet(mode: $0) }
    }

    private var indexesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Indexes")
                .font(.jbMono(12.5, .bold)).foregroundStyle(KTColor.ink3)
                .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 8)
            ForEach(vm.currentIndexes) { index in
                HStack(spacing: 8) {
                    Image(systemName: index.isUnique ? "lock" : "number")
                        .font(.system(size: 10)).foregroundStyle(KTColor.muted)
                    Text(index.name).font(.jbMono(13)).foregroundStyle(KTColor.ink2)
                    Text(index.columns.joined(separator: ", "))
                        .font(.jbMono(12.5)).foregroundStyle(KTColor.muted).lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 7)
                .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sepFaint).frame(height: 0.5) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ddlToolbar: some View {
        HStack(spacing: 8) {
            ddlButton("plus.rectangle", "New Table", enabled: vm.selectedDatabase != nil) {
                ddlSheet = .createTable
            }
            ddlButton("plus", "Add Column", enabled: vm.selectedTable != nil) {
                ddlSheet = .addColumn
            }
            ddlButton("minus", "Drop Column", enabled: selectedColumn != nil) {
                vm.prepareDropColumn(selectedColumn ?? "")
            }
            ddlButton("trash", "Drop Table", tint: KTColor.danger, enabled: vm.selectedTable != nil) {
                vm.prepareDropTable()
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sep).frame(height: 0.5) }
    }

    private func ddlButton(_ symbol: String, _ title: String, tint: Color = KTColor.ink2,
                           enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.jbMono(12, .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(KTColor.btnBorder, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func columnWidths(total: CGFloat) -> [CGFloat] {
        let sum = weights.reduce(0, +)
        return weights.map { $0 / sum * max(total, 560) }
    }

    private func headerRow(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, title in
                Text(title)
                    .font(.jbMono(12.5, .regular))
                    .foregroundStyle(KTColor.ink3)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .frame(width: widths[index], alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xF7F7FA))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xE6E6EC)).frame(height: 0.5) }
    }

    private func rows(_ widths: [CGFloat]) -> some View {
        ForEach(vm.currentColumns) { column in
            HStack(spacing: 0) {
                cell(column.name, width: widths[0], font: .jbMono(13, .regular), color: KTColor.ink)
                cell(column.dataType, width: widths[1], font: .jbMono(13), color: Color(hex: 0x8B5CF6))
                cell(column.isNullable ? "YES" : "NO", width: widths[2], font: .jbMono(13), color: KTColor.ink3)
                keyCell(column, width: widths[3])
                cell(column.defaultValue ?? "—", width: widths[4], font: .jbMono(13), color: KTColor.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedColumn == column.name ? KTColor.accentSoft : Color.clear)
            .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sepFaint).frame(height: 0.5) }
            .contentShape(Rectangle())
            .onTapGesture { selectedColumn = column.name }
        }
    }

    private func cell(_ text: String, width: CGFloat, font: Font, color: Color) -> some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func keyCell(_ column: ColumnInfo, width: CGFloat) -> some View {
        HStack {
            if column.isPrimaryKey {
                Text("PK")
                    .font(.jbMono(11, .bold))
                    .foregroundStyle(KTColor.accent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color(hex: 0xEAF1FF)))
            } else {
                Text("").frame(height: 1)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .frame(width: width, alignment: .leading)
    }

    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle").font(.system(size: 42, weight: .light)).foregroundStyle(KTColor.faint)
            Text(message).font(.jbMono(13)).foregroundStyle(KTColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
