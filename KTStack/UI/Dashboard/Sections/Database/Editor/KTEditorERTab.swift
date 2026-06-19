import SwiftUI
import KTStackKit

struct KTEditorERTab: View {
    @EnvironmentObject private var vm: DatabaseViewModel

    @State private var zoom: CGFloat = 1
    @State private var gestureZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var gesturePan: CGSize = .zero

    private static let cardTints = [KTIconTint.code, KTIconTint.cube, KTIconTint.db, KTIconTint.globe]

    private var layout: ERDiagramLayout {
        let catalog = vm.schemaCatalog
        guard !catalog.tables.isEmpty else { return .empty }
        let pkByTable = Dictionary(uniqueKeysWithValues: catalog.tables.map { ($0, Set<String>()) })
        return ERLayoutEngine.layout(tables: catalog.tables,
                                     columnsByTable: catalog.columnsByTable,
                                     primaryKeysByTable: pkByTable,
                                     relations: catalog.relations)
    }

    var body: some View {
        Group {
            if vm.schemaCatalog.tables.isEmpty {
                placeholder
            } else {
                canvas
            }
        }
        .task(id: vm.selectedDatabase) { await vm.loadRelationsIfNeeded() }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let current = layout
            ZStack {
                dottedBackground
                ZStack(alignment: .topLeading) {
                    edges(current)
                    ForEach(Array(current.nodes.enumerated()), id: \.element.id) { index, node in
                        card(node, tint: Self.cardTints[index % Self.cardTints.count])
                            .position(x: node.rect.midX, y: node.rect.midY)
                    }
                }
                .frame(width: max(current.canvasSize.width, proxy.size.width),
                       height: max(current.canvasSize.height, proxy.size.height),
                       alignment: .topLeading)
                .scaleEffect(zoom * gestureZoom, anchor: .topLeading)
                .offset(x: pan.width + gesturePan.width, y: pan.height + gesturePan.height)
            }
            .contentShape(Rectangle())
            .gesture(panGesture)
            .gesture(zoomGesture)
            .overlay(alignment: .bottomTrailing) { zoomControls }
        }
    }

    private var dottedBackground: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 22
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)),
                             with: .color(Color(hex: 0xE4E4EA)))
                    x += spacing
                }
                y += spacing
            }
        }
        .background(Color(hex: 0xFAFAFC))
    }

    private func edges(_ layout: ERDiagramLayout) -> some View {
        Canvas { ctx, _ in
            for edge in layout.edges {
                var path = Path()
                path.move(to: edge.fromPoint)
                let dx = (edge.toPoint.x - edge.fromPoint.x) * 0.5
                path.addCurve(to: edge.toPoint,
                              control1: CGPoint(x: edge.fromPoint.x + dx, y: edge.fromPoint.y),
                              control2: CGPoint(x: edge.toPoint.x - dx, y: edge.toPoint.y))
                ctx.stroke(path, with: .color(Color(hex: 0xC0C8D8)), lineWidth: 1.6)
                for point in [edge.fromPoint, edge.toPoint] {
                    ctx.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                             with: .color(KTColor.accent))
                }
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .allowsHitTesting(false)
    }

    private func card(_ node: ERTableNode, tint: KTTint) -> some View {
        VStack(spacing: 0) {
            Text(node.table)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(tint.fg)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.bg)
            ForEach(Array(node.columns.enumerated()), id: \.offset) { index, column in
                columnRow(node, column: column)
                if index < node.columns.count - 1 {
                    Rectangle().fill(KTColor.sepFaint).frame(height: 0.5)
                }
            }
        }
        .frame(width: node.rect.width, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(hex: 0xE0E0E8), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 4)
    }

    private func columnRow(_ node: ERTableNode, column: String) -> some View {
        let isPK = node.primaryKeyColumns.contains(column)
        let isFK = node.foreignKeyColumns.contains(column)
        return HStack(spacing: 4) {
            Text(column)
                .font(.system(size: 12, weight: isPK ? .bold : .regular, design: .monospaced))
                .foregroundStyle(isPK ? KTColor.ink : KTColor.ink2)
                .lineLimit(1)
            if isFK {
                Text("· FK").font(.system(size: 11, design: .monospaced)).foregroundStyle(KTColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 42, weight: .light)).foregroundStyle(KTColor.faint)
            Text("No tables").font(.system(size: 16, weight: .semibold)).foregroundStyle(KTColor.ink3)
            Text("Select a database with tables to see its ER diagram.")
                .font(.system(size: 13)).foregroundStyle(KTColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { gesturePan = $0.translation }
            .onEnded { value in
                pan.width += value.translation.width
                pan.height += value.translation.height
                gesturePan = .zero
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { gestureZoom = $0 }
            .onEnded { value in
                zoom = max(0.25, min(3, zoom * value))
                gestureZoom = 1
            }
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            zoomButton("minus") { zoom = max(0.25, zoom / 1.2) }
            Button { zoom = 1; pan = .zero } label: {
                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(KTColor.ink2)
                    .frame(minWidth: 44, minHeight: 26)
            }
            .buttonStyle(.plain)
            zoomButton("plus") { zoom = min(3, zoom * 1.2) }
        }
        .padding(.horizontal, 6)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(KTColor.btnBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .padding(16)
    }

    private func zoomButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KTColor.ink3).frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
