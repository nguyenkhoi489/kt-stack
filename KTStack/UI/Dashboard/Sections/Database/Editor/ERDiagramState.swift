import SwiftUI
import KTStackKit

@MainActor
final class ERDiagramState: ObservableObject {
    @Published private(set) var graph: ERSchemaGraph = .empty
    @Published private(set) var cachedRects: [String: CGRect] = [:]
    @Published private(set) var canvasSize: CGSize = .zero
    @Published var magnification: CGFloat = 1
    @Published var canvasOffset: CGPoint = .zero
    @Published var selectedTable: String?
    @Published private(set) var draggingTable: String?
    @Published private(set) var isCompact = false

    var viewportSize: CGSize = .zero
    var isMouseOverCanvas = false
    @Published private(set) var needsInitialFit = true

    private var computedPositions: [String: CGPoint] = [:]
    private var positionOverrides: [String: CGPoint] = [:]
    private var lastCatalog: SchemaCatalog?
    private var connectionKey = ""
    private var schemaKey = ""
    private var layoutTask: Task<Void, Never>?
    private var dragNodeStart: CGPoint?
    private var panStart: CGPoint?

    var isEmpty: Bool { graph.nodes.isEmpty }

    func apply(catalog: SchemaCatalog, connectionKey: String, schemaKey: String) {
        if connectionKey != self.connectionKey || schemaKey != self.schemaKey {
            self.connectionKey = connectionKey
            self.schemaKey = schemaKey
            positionOverrides = [:]
            selectedTable = nil
        }
        lastCatalog = catalog
        rebuildGraph(resetFit: true)
    }

    func setCompact(_ compact: Bool) {
        guard compact != isCompact else { return }
        isCompact = compact
        rebuildGraph(resetFit: false)
    }

    func resetLayout() {
        positionOverrides.removeAll()
        ERPositionStore.clear(connectionKey: connectionKey, schemaKey: schemaKey)
        rebuildGraph(resetFit: true)
    }

    func consumeInitialFit() { needsInitialFit = false }

    private func rebuildGraph(resetFit: Bool) {
        guard let catalog = lastCatalog, !catalog.detailedColumnsByTable.isEmpty else {
            graph = .empty; cachedRects = [:]; computedPositions = [:]; canvasSize = .zero
            return
        }
        let built = ERSchemaGraphBuilder.build(
            detailedColumns: catalog.detailedColumnsByTable,
            relations: catalog.relations,
            compact: isCompact)
        graph = built
        loadOverrides()
        layoutTask?.cancel()
        layoutTask = Task {
            let positions = await Task.detached { ERSugiyamaLayout.compute(graph: built) }.value
            guard !Task.isCancelled else { return }
            self.computedPositions = positions
            self.rebuildRects()
            if resetFit { self.needsInitialFit = true }
            if self.needsInitialFit && self.viewportSize.width > 0 {
                self.fitToWindow()
                self.needsInitialFit = false
            }
        }
    }

    private func loadOverrides() {
        guard !connectionKey.isEmpty else { return }
        let stored = ERPositionStore.load(connectionKey: connectionKey, schemaKey: schemaKey)
        let tableNames = Set(graph.nodes.map(\.table))
        positionOverrides = positionOverrides.filter { tableNames.contains($0.key) }
        for (table, point) in stored where tableNames.contains(table) && positionOverrides[table] == nil {
            positionOverrides[table] = point
        }
    }

    private func position(for table: String) -> CGPoint {
        positionOverrides[table] ?? computedPositions[table] ?? .zero
    }

    private func rebuildRects() {
        var rects: [String: CGRect] = [:]
        for node in graph.nodes {
            let center = position(for: node.id)
            let height = ERSugiyamaLayout.estimateHeight(columnCount: node.displayColumns.count)
            rects[node.id] = CGRect(
                x: center.x - ERSugiyamaLayout.nodeWidth / 2,
                y: center.y - height / 2,
                width: ERSugiyamaLayout.nodeWidth,
                height: height)
        }
        cachedRects = rects
        canvasSize = ERRectIndex.canvasSize(rects: rects)
    }

    func tableAt(viewPoint: CGPoint) -> String? {
        let canvasPoint = CGPoint(
            x: (viewPoint.x - canvasOffset.x) / magnification,
            y: (viewPoint.y - canvasOffset.y) / magnification)
        for (table, rect) in cachedRects where rect.contains(canvasPoint) {
            return table
        }
        return nil
    }

    func beginDrag(at startLocation: CGPoint) {
        if let table = tableAt(viewPoint: startLocation) {
            draggingTable = table
            dragNodeStart = position(for: table)
            selectedTable = table
        } else {
            panStart = canvasOffset
        }
    }

    func updateDrag(translation: CGSize) {
        if let table = draggingTable, let start = dragNodeStart {
            let center = CGPoint(
                x: start.x + translation.width / magnification,
                y: start.y + translation.height / magnification)
            positionOverrides[table] = center
            let height = ERSugiyamaLayout.estimateHeight(
                columnCount: graph.nodes.first { $0.id == table }?.displayColumns.count ?? 1)
            cachedRects[table] = CGRect(
                x: center.x - ERSugiyamaLayout.nodeWidth / 2,
                y: center.y - height / 2,
                width: ERSugiyamaLayout.nodeWidth,
                height: height)
            canvasSize = ERRectIndex.canvasSize(rects: cachedRects)
        } else if let panStart {
            canvasOffset = CGPoint(x: panStart.x + translation.width, y: panStart.y + translation.height)
        }
    }

    func endDrag() {
        if draggingTable != nil { persistOverrides() }
        draggingTable = nil
        dragNodeStart = nil
        panStart = nil
    }

    private func persistOverrides() {
        guard !connectionKey.isEmpty else { return }
        ERPositionStore.save(positionOverrides, connectionKey: connectionKey, schemaKey: schemaKey)
    }

    func zoom(to newMagnification: CGFloat, anchor: CGPoint? = nil) {
        let clamped = max(0.25, min(3.0, newMagnification))
        let center = anchor ?? CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let canvasPoint = CGPoint(
            x: (center.x - canvasOffset.x) / magnification,
            y: (center.y - canvasOffset.y) / magnification)
        canvasOffset = CGPoint(
            x: center.x - canvasPoint.x * clamped,
            y: center.y - canvasPoint.y * clamped)
        magnification = clamped
    }

    func fitToWindow() {
        guard !graph.nodes.isEmpty, viewportSize.width > 0, viewportSize.height > 0 else { return }
        let size = canvasSize
        guard size.width > 0, size.height > 0 else { return }
        let padding: CGFloat = 40
        let scaleX = (viewportSize.width - padding * 2) / size.width
        let scaleY = (viewportSize.height - padding * 2) / size.height
        let fitScale = max(0.25, min(1.0, min(scaleX, scaleY)))
        magnification = fitScale
        canvasOffset = CGPoint(
            x: (viewportSize.width - size.width * fitScale) / 2,
            y: (viewportSize.height - size.height * fitScale) / 2)
    }
}
