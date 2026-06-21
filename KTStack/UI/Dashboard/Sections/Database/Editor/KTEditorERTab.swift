import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KTStackKit

struct KTEditorERTab: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    @StateObject private var state = ERDiagramState()

    @State private var scrollMonitor: Any?
    @State private var hoverCursor: NSCursor?
    @State private var magnifyStartMag: CGFloat?

    var body: some View {
        Group {
            if state.isEmpty {
                placeholder
            } else {
                diagram
            }
        }
        .task(id: vm.selectedDatabase) {
            await vm.ensureDetailedColumnsLoaded()
            await vm.loadRelationsIfNeeded()
            syncState()
        }
        .onChange(of: vm.schemaCatalog) { _ in syncState() }
    }

    private func syncState() {
        state.apply(catalog: vm.schemaCatalog,
                    connectionKey: vm.selectedProfile?.id.uuidString ?? "none",
                    schemaKey: vm.selectedDatabase ?? "none")
    }

    private var diagram: some View {
        GeometryReader { proxy in
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(dottedBackground)
                .contentShape(Rectangle())
                .clipped()
                .gesture(dragGesture.simultaneously(with: magnifyGesture))
                .onContinuousHover { updateHover($0) }
                .onTapGesture { state.selectedTable = state.tableAt(viewPoint: $0) }
                .overlay(alignment: .bottomTrailing) { toolbar }
                .onAppear {
                    state.viewportSize = proxy.size
                    attachScrollMonitor()
                    fitIfNeeded(size: proxy.size)
                }
                .onChange(of: proxy.size) { newSize in
                    state.viewportSize = newSize
                    fitIfNeeded(size: newSize)
                }
                .onChange(of: state.needsInitialFit) { _ in fitIfNeeded(size: proxy.size) }
                .onDisappear { detachScrollMonitor() }
        }
    }

    private var canvas: some View {
        Canvas { context, _ in
            var ctx = context
            ctx.translateBy(x: state.canvasOffset.x, y: state.canvasOffset.y)
            ctx.scaleBy(x: state.magnification, y: state.magnification)
            EREdgeRenderer.drawEdges(context: ctx, edges: state.graph.edges, rects: state.cachedRects)
            for node in state.graph.nodes {
                guard let rect = state.cachedRects[node.id] else { continue }
                ERNodeRenderer.drawNode(context: &ctx,
                                        node: node,
                                        rect: rect,
                                        isSelected: state.selectedTable == node.id)
            }
        }
    }

    private func fitIfNeeded(size: CGSize) {
        guard state.needsInitialFit, size.width > 0, !state.isEmpty, state.canvasSize.width > 0 else { return }
        state.fitToWindow()
        state.consumeInitialFit()
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if state.draggingTable == nil && hoverCursor != .closedHand {
                    state.beginDrag(at: value.startLocation)
                    if state.draggingTable != nil {
                        if hoverCursor != nil { NSCursor.pop() }
                        NSCursor.closedHand.push()
                        hoverCursor = .closedHand
                    }
                }
                state.updateDrag(translation: value.translation)
            }
            .onEnded { _ in
                state.endDrag()
                if hoverCursor == .closedHand {
                    NSCursor.pop()
                    hoverCursor = nil
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if magnifyStartMag == nil { magnifyStartMag = state.magnification }
                let base = magnifyStartMag ?? state.magnification
                state.zoom(to: base * value)
            }
            .onEnded { _ in magnifyStartMag = nil }
    }

    private func updateHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            state.isMouseOverCanvas = true
            guard state.draggingTable == nil else { return }
            let desired: NSCursor? = state.tableAt(viewPoint: location) != nil ? .openHand : nil
            if desired !== hoverCursor {
                if hoverCursor != nil { NSCursor.pop() }
                desired?.push()
                hoverCursor = desired
            }
        case .ended:
            state.isMouseOverCanvas = false
            if hoverCursor != nil { NSCursor.pop(); hoverCursor = nil }
        }
    }

    private func attachScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard state.isMouseOverCanvas else { return event }
            if event.modifierFlags.contains(.command) {
                state.zoom(to: state.magnification + event.scrollingDeltaY * 0.01)
                return nil
            }
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
            state.canvasOffset = CGPoint(
                x: state.canvasOffset.x + event.scrollingDeltaX * multiplier,
                y: state.canvasOffset.y + event.scrollingDeltaY * multiplier)
            return nil
        }
    }

    private func detachScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
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
        .drawingGroup()
        .background(Color(hex: 0xFAFAFC))
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 42, weight: .light)).foregroundStyle(KTColor.faint)
            Text("No tables").font(.jbMono(16, .regular)).foregroundStyle(KTColor.ink3)
            Text("Select a database with tables to see its ER diagram.")
                .font(.jbMono(13)).foregroundStyle(KTColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            iconButton("arrow.up.left.and.arrow.down.right") { state.fitToWindow() }
            divider
            iconButton("minus") { state.zoom(to: state.magnification - 0.2) }
            Button { state.zoom(to: 1) } label: {
                Text("\(Int((state.magnification * 100).rounded()))%")
                    .font(.jbMono(12, .medium).monospacedDigit())
                    .foregroundStyle(KTColor.ink2)
                    .frame(minWidth: 44, minHeight: 26)
            }
            .buttonStyle(.plain)
            iconButton("plus") { state.zoom(to: state.magnification + 0.2) }
            divider
            iconButton(state.isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                       active: state.isCompact) { state.setCompact(!state.isCompact) }
            iconButton("arrow.counterclockwise") { state.resetLayout() }
            divider
            iconButton("square.and.arrow.up") { exportPNG() }
            iconButton("doc.on.doc") { copyToClipboard() }
        }
        .padding(.horizontal, 6)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(KTColor.btnBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .padding(16)
    }

    private var divider: some View {
        Rectangle().fill(KTColor.sepFaint).frame(width: 0.5, height: 18)
    }

    private func iconButton(_ symbol: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .regular))
                .foregroundStyle(active ? KTColor.accent : KTColor.ink3)
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @MainActor private func renderImage() -> NSImage? {
        let padding: CGFloat = 40
        let bounds = state.cachedRects.values.reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull else { return nil }
        let exportView = ERExportCanvas(
            edges: state.graph.edges,
            nodes: state.graph.nodes,
            rects: state.cachedRects,
            selected: state.selectedTable,
            offsetX: -bounds.minX + padding,
            offsetY: -bounds.minY + padding,
            width: bounds.width + padding * 2,
            height: bounds.height + padding * 2)
        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 2.0
        return renderer.nsImage
    }

    private func copyToClipboard() {
        guard let image = renderImage() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func exportPNG() {
        guard let image = renderImage(),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(vm.selectedDatabase ?? "er-diagram").png"
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            try? png.write(to: url)
        }
    }
}

private struct ERExportCanvas: View {
    let edges: [ERSchemaEdge]
    let nodes: [ERSchemaNode]
    let rects: [String: CGRect]
    let selected: String?
    let offsetX: CGFloat
    let offsetY: CGFloat
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { context, _ in
            var ctx = context
            ctx.translateBy(x: offsetX, y: offsetY)
            EREdgeRenderer.drawEdges(context: ctx, edges: edges, rects: rects)
            for node in nodes {
                guard let rect = rects[node.id] else { continue }
                ERNodeRenderer.drawNode(context: &ctx, node: node, rect: rect, isSelected: false)
            }
        }
        .frame(width: width, height: height)
        .background(Color(hex: 0xFAFAFC))
    }
}
