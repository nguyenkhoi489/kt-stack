import AppKit
import KTStackKit
import SwiftUI

struct KTDataGrid: NSViewRepresentable {
    let result: QueryResult
    var selectedRow: Binding<Int?>?
    var onActivate: ((Int) -> Void)?
    var onNearEnd: (() -> Void)?
    var sort: SortSpec?
    var onSortColumn: ((String) -> Void)?
    var editableColumns: Set<String> = []
    var onCommitEdit: ((Int, Int, String) -> Void)?
    var foreignKeyColumns: Set<String> = []
    var onNavigateFK: ((Int, Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(result: result)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let table = KTGridTableView()
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = Coordinator.gridBackground
        table.gridStyleMask = [.solidVerticalGridLineMask, .solidHorizontalGridLineMask]
        table.gridColor = Coordinator.gridLineColor
        table.allowsColumnResizing = true
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.rowHeight = 22
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = true
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.handleDoubleClick)
        table.onCopy = { [weak coordinator] in
            coordinator?.copySelectedRows(includeHeaders: false, asCSV: false)
        }
        table.menu = coordinator.makeContextMenu()
        coordinator.table = table
        coordinator.rebuildColumns(for: result)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Coordinator.gridBackground
        scroll.contentView.postsBoundsChangedNotifications = true
        coordinator.observe(scroll)
        return scroll
    }

    func updateNSView(_: NSScrollView, context: Context) {
        context.coordinator.selectedRow = selectedRow
        context.coordinator.onActivate = onActivate
        context.coordinator.onNearEnd = onNearEnd
        context.coordinator.sort = sort
        context.coordinator.onSortColumn = onSortColumn
        context.coordinator.editableColumns = editableColumns
        context.coordinator.onCommitEdit = onCommitEdit
        context.coordinator.foreignKeyColumns = foreignKeyColumns
        context.coordinator.onNavigateFK = onNavigateFK
        context.coordinator.apply(result)
    }

    static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        private(set) var result: QueryResult
        weak var table: NSTableView?
        weak var scrollView: NSScrollView?
        var selectedRow: Binding<Int?>?
        var onActivate: ((Int) -> Void)?
        var onNearEnd: (() -> Void)?
        var sort: SortSpec?
        var onSortColumn: ((String) -> Void)?
        var editableColumns: Set<String> = []
        var onCommitEdit: ((Int, Int, String) -> Void)?
        var foreignKeyColumns: Set<String> = []
        var onNavigateFK: ((Int, Int) -> Void)?
        private var nearEndRequested = false
        private weak var editingField: NSTextField?
        private var editingRow = -1
        private var editingColumn = -1
        private var committedEdit = false

        static let cellFont: NSFont =
            .init(name: "JetBrainsMono-Medium", size: 12.5)
                ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        static let headerFont: NSFont =
            .init(name: "JetBrainsMono-SemiBold", size: 11)
                ?? .monospacedSystemFont(ofSize: 11, weight: .semibold)
        static let nullFont: NSFont = {
            let base = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: 12.5) ?? base
        }()

        static let gridBackground = NSColor(hexValue: 0xFFFFFF)
        static let headerBackground = NSColor(hexValue: 0xF7F7FA)
        static let textColor = NSColor(hexValue: 0x1D1D1F)
        static let nullColor = NSColor(hexValue: 0x9A9AA5)
        static let editingColor = NSColor(hexValue: 0xE6EDFF)
        static let editingTextColor = NSColor(hexValue: 0x1D1D1F)
        static let foreignKeyColor = NSColor(hexValue: 0x2F6BFF)
        static let numberColor = NSColor(hexValue: 0xB26A00)
        static let gridLineColor = NSColor(hexValue: 0xECECF1)
        static let rownumText = NSColor(hexValue: 0x9A9AA5)
        static let rownumBg = NSColor(hexValue: 0xFAFAFC)
        static let rownumIdentifier = "rownum"

        private func dataIndex(of tableColumn: NSTableColumn?) -> Int? {
            guard let raw = tableColumn?.identifier.rawValue, raw.hasPrefix("col-") else { return nil }
            return Int(raw.dropFirst(4))
        }

        private func dataIndex(ofViewColumn viewColumn: Int) -> Int? {
            guard let table, viewColumn >= 0, viewColumn < table.tableColumns.count else { return nil }
            return dataIndex(of: table.tableColumns[viewColumn])
        }

        static func isNumeric(_ cell: Cell) -> Bool {
            switch cell {
            case .int, .double: true
            default: false
            }
        }

        init(result: QueryResult) {
            self.result = result
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        func observe(_ scroll: NSScrollView) {
            scrollView = scroll
            NotificationCenter.default.addObserver(
                self, selector: #selector(boundsDidChange),
                name: NSView.boundsDidChangeNotification, object: scroll.contentView
            )
        }

        func stopObserving() {
            NotificationCenter.default.removeObserver(self)
        }

        @objc
        private func boundsDidChange() {
            guard let scroll = scrollView, let table, !result.rows.isEmpty else { return }
            if editingField != nil { table.window?.makeFirstResponder(table) }
            let documentHeight = table.bounds.height
            let viewportHeight = scroll.contentView.bounds.height
            guard documentHeight > viewportHeight else { return }
            let fraction = scroll.contentView.documentVisibleRect.maxY / documentHeight
            if fraction <= 0.8 {
                nearEndRequested = false
                return
            }
            guard !nearEndRequested else { return }
            nearEndRequested = true
            onNearEnd?()
        }

        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.addItem(withTitle: "Copy", action: #selector(copyTSV), keyEquivalent: "")
            menu.addItem(withTitle: "Copy with Headers", action: #selector(copyTSVWithHeaders), keyEquivalent: "")
            menu.addItem(withTitle: "Copy as CSV", action: #selector(copyCSV), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Follow Foreign Key", action: #selector(followForeignKey), keyEquivalent: "")
            menu.addItem(withTitle: "Edit Row…", action: #selector(editRow), keyEquivalent: "")
            menu.items.forEach { $0.target = self }
            return menu
        }

        @objc
        private func followForeignKey() {
            guard let grid = table as? KTGridTableView, grid.menuRow >= 0,
                  grid.menuRow < result.rows.count,
                  let column = dataIndex(ofViewColumn: grid.menuColumn),
                  column < result.columns.count else { return }
            onNavigateFK?(grid.menuRow, column)
        }

        @objc
        private func copyTSV() {
            copySelectedRows(includeHeaders: false, asCSV: false)
        }

        @objc
        private func copyTSVWithHeaders() {
            copySelectedRows(includeHeaders: true, asCSV: false)
        }

        @objc
        private func copyCSV() {
            copySelectedRows(includeHeaders: true, asCSV: true)
        }

        @objc
        private func editRow() {
            guard let onActivate, let row = table?.selectedRowIndexes.first,
                  row < result.rows.count else { return }
            onActivate(row)
        }

        func validateMenuItem(_ item: NSMenuItem) -> Bool {
            if item.action == #selector(editRow) {
                return onActivate != nil && !(table?.selectedRowIndexes.isEmpty ?? true)
            }
            if item.action == #selector(followForeignKey) {
                guard onNavigateFK != nil, let grid = table as? KTGridTableView,
                      grid.menuRow >= 0, grid.menuRow < result.rows.count,
                      let column = dataIndex(ofViewColumn: grid.menuColumn),
                      column < result.columns.count else { return false }
                return foreignKeyColumns.contains(result.columns[column].name)
                    && result.rows[grid.menuRow][column] != .null
            }
            return true
        }

        func copySelectedRows(includeHeaders: Bool, asCSV: Bool) {
            let selected = table?.selectedRowIndexes ?? []
            let indices: [Int]? = selected.isEmpty ? nil : Array(selected).sorted()
            let text = asCSV
                ? QueryResultTextSerializer.csv(result, rows: indices, includeHeaders: includeHeaders)
                : QueryResultTextSerializer.tsv(result, rows: indices, includeHeaders: includeHeaders)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }

        func apply(_ newResult: QueryResult) {
            let columnsChanged = newResult.columns != result.columns
            let rowCountChanged = newResult.rows.count != result.rows.count
            result = newResult
            if columnsChanged { rebuildColumns(for: newResult) }
            if rowCountChanged { nearEndRequested = false }
            table?.reloadData()
            updateSortIndicators()
        }

        func tableView(_: NSTableView, didClick tableColumn: NSTableColumn) {
            guard let onSortColumn, tableColumn.identifier.rawValue != Self.rownumIdentifier else { return }
            onSortColumn(tableColumn.title)
        }

        func tableView(_ tableView: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("ktgridrow")
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? KTGridRowView {
                return reused
            }
            let rowView = KTGridRowView()
            rowView.identifier = identifier
            return rowView
        }

        private func updateSortIndicators() {
            guard let table else { return }
            for column in table.tableColumns {
                if let sort, column.title == sort.column {
                    table.setIndicatorImage(
                        NSImage(
                            systemSymbolName: sort.ascending ? "chevron.up" : "chevron.down",
                            accessibilityDescription: nil
                        ),
                        in: column
                    )
                    table.highlightedTableColumn = column
                } else {
                    table.setIndicatorImage(nil, in: column)
                }
            }
        }

        func rebuildColumns(for result: QueryResult) {
            guard let table else { return }
            for column in table.tableColumns {
                table.removeTableColumn(column)
            }
            let rownum = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.rownumIdentifier))
            rownum.title = ""
            rownum.width = 50; rownum.minWidth = 40; rownum.maxWidth = 72
            rownum.headerCell.drawsBackground = true
            rownum.headerCell.backgroundColor = Self.headerBackground
            table.addTableColumn(rownum)
            for (index, meta) in result.columns.enumerated() {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col-\(index)"))
                column.title = meta.name
                column.minWidth = 60
                column.width = 150
                column.headerCell.font = Self.headerFont
                column.headerCell.drawsBackground = true
                column.headerCell.backgroundColor = Self.headerBackground
                table.addTableColumn(column)
            }
        }

        func numberOfRows(in _: NSTableView) -> Int {
            result.rows.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let tableColumn, row < result.rows.count else { return nil }

            if tableColumn.identifier.rawValue == Self.rownumIdentifier {
                let rownumID = NSUserInterfaceItemIdentifier("rownumcell")
                let cell = (tableView.makeView(withIdentifier: rownumID, owner: self) as? NSTextField)
                    ?? Self.makeCell(identifier: rownumID)
                cell.delegate = nil
                cell.isEditable = false
                cell.stringValue = "\(row + 1)"
                cell.textColor = Self.rownumText
                cell.alignment = .right
                cell.drawsBackground = true
                cell.backgroundColor = Self.rownumBg
                return cell
            }

            guard let columnIndex = dataIndex(of: tableColumn),
                  columnIndex < result.rows[row].count else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("cell")
            let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField)
                ?? Self.makeCell(identifier: identifier)

            field.delegate = self
            field.isEditable = false
            field.drawsBackground = false
            let cell = result.rows[row][columnIndex]
            if let text = cell.displayText {
                field.font = Self.cellFont
                field.stringValue = text
                if foreignKeyColumns.contains(result.columns[columnIndex].name) {
                    field.textColor = Self.foreignKeyColor
                    field.alignment = .left
                } else if Self.isNumeric(cell) {
                    field.textColor = Self.numberColor
                    field.alignment = .right
                } else {
                    field.textColor = Self.textColor
                    field.alignment = .left
                }
            } else {
                field.font = Self.nullFont
                field.stringValue = "NULL"
                field.textColor = Self.nullColor
                field.alignment = .left
            }
            return field
        }

        func tableViewSelectionDidChange(_: Notification) {
            guard let table else { return }
            let indexes = table.selectedRowIndexes
            selectedRow?.wrappedValue = indexes.count == 1 ? indexes.first : nil
        }

        @objc
        func handleDoubleClick() {
            guard let table, table.clickedRow >= 0, table.clickedRow < result.rows.count else { return }
            let row = table.clickedRow
            let viewColumn = table.clickedColumn
            guard let column = dataIndex(ofViewColumn: viewColumn), cellIsInlineEditable(row: row, column: column) else {
                onActivate?(row)
                return
            }
            beginInlineEdit(row: row, viewColumn: viewColumn, dataColumn: column)
        }

        private func cellIsInlineEditable(row: Int, column: Int) -> Bool {
            guard onCommitEdit != nil, column < result.columns.count else { return false }
            guard editableColumns.contains(result.columns[column].name) else { return false }
            if case .blob = result.rows[row][column] { return false }
            return true
        }

        private func beginInlineEdit(row: Int, viewColumn: Int, dataColumn: Int) {
            guard let table,
                  let field = table.view(atColumn: viewColumn, row: row, makeIfNecessary: true) as? NSTextField
            else { return }
            committedEdit = false
            editingRow = row
            editingColumn = dataColumn
            editingField = field
            let cell = result.rows[row][dataColumn]
            field.stringValue = cell.displayText ?? ""
            field.textColor = Self.editingTextColor
            field.isEditable = true
            field.drawsBackground = true
            field.backgroundColor = Self.editingColor
            table.editColumn(viewColumn, row: row, with: nil, select: true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField, field === editingField else { return }
            let row = editingRow, column = editingColumn
            let value = field.stringValue
            let cancelled = (obj.userInfo?["NSTextMovement"] as? Int) == NSTextMovement.cancel.rawValue
            field.isEditable = false
            field.drawsBackground = false
            editingField = nil
            editingRow = -1
            editingColumn = -1
            guard !cancelled, !committedEdit, row >= 0, column >= 0 else {
                table?.reloadData()
                return
            }
            committedEdit = true
            onCommitEdit?(row, column, value)
        }

        private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
            let field = NSTextField(labelWithString: "")
            field.identifier = identifier
            field.lineBreakMode = .byTruncatingTail
            field.font = cellFont
            field.drawsBackground = false
            return field
        }
    }
}

final class KTGridTableView: NSTableView {
    var onCopy: (() -> Void)?
    private(set) var menuRow = -1
    private(set) var menuColumn = -1

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "c"
        {
            onCopy?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        menuRow = row(at: point)
        menuColumn = column(at: point)
        if menuRow >= 0, !selectedRowIndexes.contains(menuRow) {
            selectRowIndexes(IndexSet(integer: menuRow), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}

final class KTGridRowView: NSTableRowView {
    private static let selectionFill = NSColor(srgbRed: 47 / 255, green: 107 / 255, blue: 255 / 255, alpha: 0.10)

    override func drawSelection(in _: NSRect) {
        guard isSelected else { return }
        Self.selectionFill.setFill()
        bounds.fill()
    }
}

private extension NSColor {
    convenience init(hexValue: UInt32) {
        self.init(
            srgbRed: CGFloat((hexValue >> 16) & 0xFF) / 255,
            green: CGFloat((hexValue >> 8) & 0xFF) / 255,
            blue: CGFloat(hexValue & 0xFF) / 255,
            alpha: 1
        )
    }
}
