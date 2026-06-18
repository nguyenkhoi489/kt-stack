import SwiftUI
import KDWarmKit

struct ERDiagramView: View {

    @EnvironmentObject private var vm: DatabaseViewModel

    @State private var zoom: CGFloat = 1
    @State private var gestureZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var gesturePan: CGSize = .zero

    private var layout: ERDiagramLayout {
        let catalog = vm.schemaCatalog
        guard !catalog.tables.isEmpty else { return .empty }
        let pkByTable = Dictionary(uniqueKeysWithValues: catalog.tables.map { table in
            (table, Set<String>())
        })
        return ERLayoutEngine.layout(
            tables: catalog.tables,
            columnsByTable: catalog.columnsByTable,
            primaryKeysByTable: pkByTable,
            relations: catalog.relations)
    }

    var body: some View {
        Group {
            if vm.schemaCatalog.tables.isEmpty {
                EmptyStateView(symbol: "rectangle.connected.to.line.below",
                               title: "No tables",
                               message: "Select a database with tables to see its ER diagram.")
            } else {
                diagramCanvas
            }
        }
        .task(id: vm.selectedDatabase) {
            await vm.loadRelationsIfNeeded()
        }
    }

    private var diagramCanvas: some View {
        GeometryReader { proxy in
            let currentLayout = layout
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                ZStack(alignment: .topLeading) {
                    edgesCanvas(layout: currentLayout)
                    ForEach(currentLayout.nodes) { node in
                        tableNodeView(node)
                            .position(x: node.rect.midX, y: node.rect.midY)
                    }
                }
                .frame(width: max(currentLayout.canvasSize.width, proxy.size.width),
                       height: max(currentLayout.canvasSize.height, proxy.size.height),
                       alignment: .topLeading)
                .scaleEffect(zoom * gestureZoom, anchor: .topLeading)
                .offset(x: pan.width + gesturePan.width,
                        y: pan.height + gesturePan.height)
            }
            .contentShape(Rectangle())
            .gesture(panGesture)
            .gesture(zoomGesture)
            .overlay(alignment: .bottomTrailing) { zoomControls }
        }
    }

    private func edgesCanvas(layout: ERDiagramLayout) -> some View {
        Canvas { ctx, _ in
            for edge in layout.edges {
                var path = Path()
                path.move(to: edge.fromPoint)
                let dx = (edge.toPoint.x - edge.fromPoint.x) * 0.5
                let control1 = CGPoint(x: edge.fromPoint.x + dx, y: edge.fromPoint.y)
                let control2 = CGPoint(x: edge.toPoint.x - dx, y: edge.toPoint.y)
                path.addCurve(to: edge.toPoint, control1: control1, control2: control2)
                ctx.stroke(path, with: .color(.secondary), lineWidth: 1.5)

                let arrow = arrowHead(at: edge.toPoint, from: control2)
                ctx.fill(arrow, with: .color(.secondary))
            }
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
        .allowsHitTesting(false)
    }

    private func arrowHead(at tip: CGPoint, from origin: CGPoint) -> Path {
        let angle = atan2(tip.y - origin.y, tip.x - origin.x)
        let size: CGFloat = 8
        let left = CGPoint(x: tip.x - size * cos(angle - .pi / 6),
                           y: tip.y - size * sin(angle - .pi / 6))
        let right = CGPoint(x: tip.x - size * cos(angle + .pi / 6),
                            y: tip.y - size * sin(angle + .pi / 6))
        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }

    private func tableNodeView(_ node: ERTableNode) -> some View {
        VStack(spacing: 0) {
            Text(node.table)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .padding(.horizontal, KDSpacing.space2)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.18))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(node.columns, id: \.self) { column in
                    HStack(spacing: KDSpacing.space1) {
                        if node.primaryKeyColumns.contains(column) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                        } else if node.foreignKeyColumns.contains(column) {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                                .foregroundStyle(.blue)
                        } else {
                            Spacer().frame(width: 10)
                        }
                        Text(column)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, KDSpacing.space2)
                    .frame(height: 18)
                }
            }
        }
        .frame(width: node.rect.width, height: node.rect.height, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
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
        HStack(spacing: KDSpacing.space1) {
            Button { adjustZoom(by: 1 / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }
            Button { resetView() } label: { Text("\(Int((zoom * 100).rounded()))%").monospacedDigit() }
            Button { adjustZoom(by: 1.2) } label: { Image(systemName: "plus.magnifyingglass") }
        }
        .buttonStyle(.bordered)
        .padding(KDSpacing.space3)
    }

    private func adjustZoom(by factor: CGFloat) {
        zoom = max(0.25, min(3, zoom * factor))
    }

    private func resetView() {
        zoom = 1
        pan = .zero
    }
}
