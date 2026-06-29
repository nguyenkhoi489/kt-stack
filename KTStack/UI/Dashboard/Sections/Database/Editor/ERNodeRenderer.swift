import KTStackKit
import SwiftUI

enum ERNodeRenderer {
    private static let cornerRadius: CGFloat = 8
    private static let maxTableNameChars = 24
    private static let maxTypeChars = 18
    private static let iconXOffset: CGFloat = 10
    private static let headerTextXOffset: CGFloat = 28
    private static let badgeXOffset: CGFloat = 14
    private static let columnNameXOffset: CGFloat = 24
    private static let typeRightMargin: CGFloat = 10

    static func drawNode(
        context: inout GraphicsContext,
        node: ERSchemaNode,
        rect: CGRect,
        isSelected: Bool
    ) {
        let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
        context.fill(path, with: .color(KTEditorTheme.content2))
        context.stroke(
            path,
            with: .color(isSelected ? KTEditorTheme.accent : KTEditorTheme.separator),
            lineWidth: isSelected ? 2 : 1
        )

        let headerHeight = ERSugiyamaLayout.headerHeight
        let headerRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerHeight)
        let headerPath = Path { p in
            p.addRoundedRect(
                in: headerRect,
                cornerRadii: RectangleCornerRadii(topLeading: cornerRadius, topTrailing: cornerRadius)
            )
        }
        context.fill(headerPath, with: .color(KTEditorTheme.accentSoft))

        let icon = Text(Image(systemName: "tablecells"))
            .font(.system(size: 11)).foregroundColor(KTEditorTheme.accent)
        context.draw(
            context.resolve(icon),
            at: CGPoint(x: rect.minX + iconXOffset, y: rect.minY + headerHeight / 2),
            anchor: .leading
        )

        let displayName = truncate(node.table, max: maxTableNameChars)
        let title = Text(displayName).font(.jbMono(12, .semibold)).foregroundColor(KTEditorTheme.label)
        context.draw(
            context.resolve(title),
            at: CGPoint(x: rect.minX + headerTextXOffset, y: rect.minY + headerHeight / 2),
            anchor: .leading
        )

        let dividerY = rect.minY + headerHeight
        var divider = Path()
        divider.move(to: CGPoint(x: rect.minX, y: dividerY))
        divider.addLine(to: CGPoint(x: rect.maxX, y: dividerY))
        context.stroke(divider, with: .color(KTEditorTheme.separator), lineWidth: 1)

        var clipped = context
        clipped.clip(to: path)
        let rowHeight = ERSugiyamaLayout.columnRowHeight
        for (index, column) in node.displayColumns.enumerated() {
            let rowY = dividerY + CGFloat(index) * rowHeight + rowHeight / 2
            drawBadge(for: column, into: &clipped, at: CGPoint(x: rect.minX + badgeXOffset, y: rowY))

            let name = Text(column.name)
                .font(.jbMono(11, column.isPrimaryKey ? .semibold : .regular))
                .foregroundColor(column.isPrimaryKey ? KTEditorTheme.label : KTEditorTheme.label2)
            clipped.draw(
                clipped.resolve(name),
                at: CGPoint(x: rect.minX + columnNameXOffset, y: rowY),
                anchor: .leading
            )

            let type = Text(truncate(column.dataType, max: maxTypeChars))
                .font(.jbMono(11)).foregroundColor(KTEditorTheme.label2)
            clipped.draw(
                clipped.resolve(type),
                at: CGPoint(x: rect.maxX - typeRightMargin, y: rowY),
                anchor: .trailing
            )
        }
    }

    private static func drawBadge(
        for column: ERColumn,
        into context: inout GraphicsContext,
        at point: CGPoint
    ) {
        let symbol: String
        let color: Color
        if column.isPrimaryKey {
            symbol = "key.fill"; color = KTEditorTheme.Status.warning
        } else if column.isForeignKey {
            symbol = "link"; color = KTEditorTheme.accent
        } else {
            return
        }
        let badge = Text(Image(systemName: symbol)).font(.system(size: 8)).foregroundColor(color)
        context.draw(context.resolve(badge), at: point, anchor: .center)
    }

    private static func truncate(_ value: String, max: Int) -> String {
        value.count > max ? String(value.prefix(max)) + "\u{2026}" : value
    }
}
