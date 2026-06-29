#if DEBUG
    import KTStackKit
    import SwiftUI

    private struct DraftERNode: Identifiable {
        let id = UUID()
        let name: String
        let origin: CGPoint
        let columns: [(badge: DraftColumnKey, name: String, type: String)]
        let selected: Bool

        var width: CGFloat {
            190
        }
    }

    struct DraftERTabView: View {
        private let nodes: [DraftERNode] = [
            DraftERNode(name: "users", origin: CGPoint(x: 60, y: 70), columns: [
                (.primary, "id", "int"),
                (.none, "email", "varchar(255)"),
                (.none, "name", "varchar(120)"),
                (.none, "created_at", "timestamp"),
            ], selected: true),
            DraftERNode(name: "orders", origin: CGPoint(x: 410, y: 190), columns: [
                (.primary, "id", "int"),
                (.foreign, "user_id", "int"),
                (.foreign, "product_id", "int"),
                (.none, "total", "decimal(10,2)"),
                (.none, "status", "varchar(24)"),
            ], selected: false),
            DraftERNode(name: "products", origin: CGPoint(x: 660, y: 300), columns: [
                (.primary, "id", "int"),
                (.none, "sku", "varchar(64)"),
                (.none, "name", "varchar(180)"),
                (.none, "price", "decimal(10,2)"),
            ], selected: false),
        ]

        var body: some View {
            DraftChrome(activeTab: .er) {
                ZStack(alignment: .topLeading) {
                    dottedBackground
                    edges
                    ForEach(nodes) { node in
                        nodeCard(node).offset(x: node.origin.x, y: node.origin.y)
                    }
                    zoomToolbar
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(16)
                }
                .clipped()
            }
        }

        private var dottedBackground: some View {
            Canvas { context, size in
                let spacing: CGFloat = 22
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = 0
                    while x < size.width {
                        let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                        context.fill(dot, with: .color(KTEditorTheme.separator))
                        x += spacing
                    }
                    y += spacing
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KTEditorTheme.content)
        }

        private var edges: some View {
            Canvas { context, _ in
                drawEdge(context, from: CGPoint(x: 250, y: 150), to: CGPoint(x: 410, y: 250))
                drawEdge(context, from: CGPoint(x: 600, y: 280), to: CGPoint(x: 660, y: 360))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private func drawEdge(_ context: GraphicsContext, from: CGPoint, to: CGPoint) {
            var path = Path()
            path.move(to: from)
            path.addCurve(
                to: to,
                control1: CGPoint(x: (from.x + to.x) / 2, y: from.y),
                control2: CGPoint(x: (from.x + to.x) / 2, y: to.y)
            )
            context.stroke(path, with: .color(KTEditorTheme.label3), lineWidth: 1.5)
        }

        private func nodeCard(_ node: DraftERNode) -> some View {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "tablecells").font(.system(size: 11)).foregroundStyle(KTEditorTheme.accent)
                    Text(node.name).font(.jbMono(12, .semibold)).foregroundStyle(KTEditorTheme.label)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(KTEditorTheme.accentSoft)

                ForEach(node.columns, id: \.name) { column in
                    HStack(spacing: 7) {
                        badge(column.badge)
                        Text(column.name).font(.jbMono(11)).foregroundStyle(KTEditorTheme.label)
                        Spacer()
                        Text(column.type).font(.jbMono(11)).foregroundStyle(KTEditorTheme.label2)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(alignment: .top) { Divider().overlay(KTEditorTheme.separator) }
                }
            }
            .frame(width: node.width)
            .background(KTEditorTheme.content, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        node.selected ? KTEditorTheme.accent : KTEditorTheme.separator,
                        lineWidth: node.selected ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }

        @ViewBuilder
        private func badge(_ key: DraftColumnKey) -> some View {
            switch key {
            case .primary: Image(systemName: "key.fill").font(.system(size: 9)).foregroundStyle(Color(hex: 0xE0A106)).frame(width: 12)
            case .foreign: Image(systemName: "link").font(.system(size: 9)).foregroundStyle(KTEditorTheme.accent).frame(width: 12)
            case .none: Color.clear.frame(width: 12, height: 1)
            }
        }

        private var zoomToolbar: some View {
            HStack(spacing: 4) {
                toolbarIcon("arrow.up.left.and.arrow.down.right")
                toolbarIcon("minus")
                Text("100%").font(.jbMono(12)).foregroundStyle(KTEditorTheme.label).frame(minWidth: 44)
                toolbarIcon("plus")
                Rectangle().fill(KTEditorTheme.separator).frame(width: 1, height: 18)
                toolbarIcon("square.grid.2x2")
                toolbarIcon("arrow.counterclockwise")
                Rectangle().fill(KTEditorTheme.separator).frame(width: 1, height: 18)
                toolbarIcon("square.and.arrow.up")
                toolbarIcon("doc.on.doc")
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(KTEditorTheme.window, in: Capsule())
            .overlay(Capsule().stroke(KTEditorTheme.btnBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }

        private func toolbarIcon(_ name: String) -> some View {
            Image(systemName: name).font(.system(size: 12)).foregroundStyle(KTEditorTheme.label2).frame(width: 26, height: 26)
        }
    }

    #if DEBUG
        #Preview {
            DraftERTabView().frame(width: 1200, height: 720)
        }
    #endif

#endif
