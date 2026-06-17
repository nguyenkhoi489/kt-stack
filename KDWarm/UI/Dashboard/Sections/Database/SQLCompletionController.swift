import AppKit
import KDWarmKit

final class SQLCompletionController: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    private weak var textView: NSTextView?
    private var items: [SQLCompletionItem] = []
    private var partial: String = ""
    private let panel: NSPanel
    private let tableView: NSTableView
    private let rowHeight: CGFloat = 20
    private let maxVisibleRows = 9
    private let panelWidth: CGFloat = 280

    var isVisible: Bool { panel.isVisible }

    init(textView: NSTextView) {
        self.textView = textView
        tableView = NSTableView()
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        super.init()
        configure()
    }

    private func configure() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("text"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = rowHeight
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(handleClick)
        tableView.refusesFirstResponder = true

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false

        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 6
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: effect.topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -4),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 2),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -2),
        ])

        panel.contentView = effect
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
    }

    func update(items: [SQLCompletionItem], partial: String) {
        guard !items.isEmpty, let textView else { hide(); return }
        self.items = items
        self.partial = partial
        tableView.reloadData()
        selectRow(0)
        position(relativeTo: textView)
        if !panel.isVisible {
            textView.window?.addChildWindow(panel, ordered: .above)
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        items = []
    }

    func moveDown() { selectRow(min(tableView.selectedRow + 1, items.count - 1)) }
    func moveUp() { selectRow(max(tableView.selectedRow - 1, 0)) }

    private func selectRow(_ index: Int) {
        guard index >= 0, index < items.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
    }

    @objc private func handleClick() { acceptSelected() }

    func acceptSelected() {
        let index = tableView.selectedRow
        guard index >= 0, index < items.count, let textView else { hide(); return }
        let replacement = items[index].text
        let range = partialRange(in: textView)
        if textView.shouldChangeText(in: range, replacementString: replacement) {
            textView.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
        }
        hide()
    }

    private func partialRange(in textView: NSTextView) -> NSRange {
        let caret = textView.selectedRange().location
        let string = textView.string as NSString
        var start = caret
        while start > 0, isIdentifier(string.character(at: start - 1)) { start -= 1 }
        return NSRange(location: start, length: caret - start)
    }

    private func isIdentifier(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return scalar == "_" || CharacterSet.alphanumerics.contains(scalar)
    }

    private func position(relativeTo textView: NSTextView) {
        let caret = textView.selectedRange().location
        let caretRect = textView.firstRect(forCharacterRange: NSRange(location: caret, length: 0),
                                           actualRange: nil)
        let rows = min(items.count, maxVisibleRows)
        let height = CGFloat(rows) * rowHeight + 8
        let origin = NSPoint(x: caretRect.minX, y: caretRect.minY - height - 4)
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: panelWidth, height: height), display: true)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField)
            ?? makeCell(identifier)
        field.attributedStringValue = highlighted(items[row])
        return field
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.identifier = identifier
        field.lineBreakMode = .byTruncatingTail
        field.drawsBackground = false
        return field
    }

    private func highlighted(_ item: SQLCompletionItem) -> NSAttributedString {
        let base = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let result = NSMutableAttributedString(string: item.text, attributes: [
            .font: base, .foregroundColor: NSColor.labelColor,
        ])
        if !partial.isEmpty, let matched = item.text.lowercased().range(of: partial.lowercased()) {
            let nsRange = NSRange(matched, in: item.text)
            result.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                .foregroundColor: NSColor.controlAccentColor,
            ], range: nsRange)
        }
        return result
    }
}
