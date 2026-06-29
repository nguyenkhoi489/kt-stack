import KTStackKit
import SwiftUI

enum EREdgeRenderer {
    private struct ResolvedEdge {
        let edge: ERSchemaEdge
        let fromRect: CGRect
        let toRect: CGRect
    }

    static func drawEdges(
        context: GraphicsContext,
        edges: [ERSchemaEdge],
        rects: [String: CGRect]
    ) {
        let strokeColor = KTEditorTheme.Status.stopped
        let strokeStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

        let resolved: [ResolvedEdge] = edges.compactMap { edge in
            guard let fromRect = rects[edge.fromTable], let toRect = rects[edge.toTable] else { return nil }
            return ResolvedEdge(edge: edge, fromRect: fromRect, toRect: toRect)
        }

        var srcCounts: [String: Int] = [:]
        var dstCounts: [String: Int] = [:]
        for item in resolved {
            srcCounts[item.edge.fromTable, default: 0] += 1
            dstCounts[item.edge.toTable, default: 0] += 1
        }

        var edgesBySource: [String: [ResolvedEdge]] = [:]
        var edgesByDest: [String: [ResolvedEdge]] = [:]
        for item in resolved {
            edgesBySource[item.edge.fromTable, default: []].append(item)
            edgesByDest[item.edge.toTable, default: []].append(item)
        }
        for key in edgesBySource.keys {
            edgesBySource[key]?.sort { $0.toRect.midX < $1.toRect.midX }
        }
        for key in edgesByDest.keys {
            edgesByDest[key]?.sort { $0.fromRect.midX < $1.fromRect.midX }
        }

        var srcPortIndex: [String: Int] = [:]
        var dstPortIndex: [String: Int] = [:]
        for (_, group) in edgesBySource {
            for (idx, item) in group.enumerated() {
                srcPortIndex[item.edge.id] = idx
            }
        }
        for (_, group) in edgesByDest {
            for (idx, item) in group.enumerated() {
                dstPortIndex[item.edge.id] = idx
            }
        }

        for item in resolved {
            let si = srcPortIndex[item.edge.id] ?? 0
            let di = dstPortIndex[item.edge.id] ?? 0
            let (srcPort, dstPort, verticalPorts) = computePorts(
                from: item.fromRect, to: item.toRect,
                srcIdx: si, srcTotal: srcCounts[item.edge.fromTable] ?? 1,
                dstIdx: di, dstTotal: dstCounts[item.edge.toTable] ?? 1
            )
            let (path, cp1, cp2) = bezierPath(from: srcPort, to: dstPort, verticalPorts: verticalPorts)
            context.stroke(path, with: .color(strokeColor), style: strokeStyle)
            drawCrowFoot(context: context, at: srcPort, toward: cp1, color: strokeColor)
            drawOneBar(context: context, at: dstPort, toward: cp2, color: strokeColor)
        }
    }

    private static func computePorts(
        from fromRect: CGRect,
        to toRect: CGRect,
        srcIdx: Int,
        srcTotal: Int,
        dstIdx: Int,
        dstTotal: Int
    ) -> (CGPoint, CGPoint, Bool) {
        let fromCenter = CGPoint(x: fromRect.midX, y: fromRect.midY)
        let toCenter = CGPoint(x: toRect.midX, y: toRect.midY)
        let verticalGap = fromCenter.y < toCenter.y
            ? toRect.minY - fromRect.maxY
            : fromRect.minY - toRect.maxY
        let minGapForVertical: CGFloat = 30

        if verticalGap > minGapForVertical {
            let srcX = spreadOffset(in: fromRect.width, index: srcIdx, total: srcTotal, base: fromRect.minX)
            let dstX = spreadOffset(in: toRect.width, index: dstIdx, total: dstTotal, base: toRect.minX)
            if fromCenter.y < toCenter.y {
                return (CGPoint(x: srcX, y: fromRect.maxY), CGPoint(x: dstX, y: toRect.minY), true)
            } else {
                return (CGPoint(x: srcX, y: fromRect.minY), CGPoint(x: dstX, y: toRect.maxY), true)
            }
        } else {
            let srcY = spreadOffset(in: fromRect.height, index: srcIdx, total: srcTotal, base: fromRect.minY)
            let dstY = spreadOffset(in: toRect.height, index: dstIdx, total: dstTotal, base: toRect.minY)
            if fromCenter.x < toCenter.x {
                return (CGPoint(x: fromRect.maxX, y: srcY), CGPoint(x: toRect.minX, y: dstY), false)
            } else {
                return (CGPoint(x: fromRect.minX, y: srcY), CGPoint(x: toRect.maxX, y: dstY), false)
            }
        }
    }

    private static func spreadOffset(in length: CGFloat, index: Int, total: Int, base: CGFloat) -> CGFloat {
        let padding: CGFloat = min(length * 0.2, 30)
        let usable = length - padding * 2
        if total <= 1 { return base + length / 2 }
        let step = usable / CGFloat(total - 1)
        return base + padding + step * CGFloat(index)
    }

    private static func bezierPath(from src: CGPoint, to dst: CGPoint, verticalPorts: Bool) -> (Path, CGPoint, CGPoint) {
        let cp1: CGPoint
        let cp2: CGPoint
        if verticalPorts {
            let offset = max(abs(dst.y - src.y) * 0.4, 20)
            cp1 = CGPoint(x: src.x, y: src.y + (dst.y > src.y ? offset : -offset))
            cp2 = CGPoint(x: dst.x, y: dst.y + (src.y > dst.y ? offset : -offset))
        } else {
            let offset = max(abs(dst.x - src.x) * 0.4, 20)
            cp1 = CGPoint(x: src.x + (dst.x > src.x ? offset : -offset), y: src.y)
            cp2 = CGPoint(x: dst.x + (src.x > dst.x ? offset : -offset), y: dst.y)
        }
        var path = Path()
        path.move(to: src)
        path.addCurve(to: dst, control1: cp1, control2: cp2)
        return (path, cp1, cp2)
    }

    private static func drawCrowFoot(context: GraphicsContext, at point: CGPoint, toward target: CGPoint, color: Color) {
        let length: CGFloat = 12
        let spread: CGFloat = 8
        let angle = atan2(target.y - point.y, target.x - point.x)
        let tip = CGPoint(x: point.x + length * cos(angle), y: point.y + length * sin(angle))
        let perpAngle = angle + .pi / 2
        let top = CGPoint(x: point.x + spread * cos(perpAngle), y: point.y + spread * sin(perpAngle))
        let bottom = CGPoint(x: point.x - spread * cos(perpAngle), y: point.y - spread * sin(perpAngle))
        var path = Path()
        path.move(to: tip); path.addLine(to: top)
        path.move(to: tip); path.addLine(to: point)
        path.move(to: tip); path.addLine(to: bottom)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    private static func drawOneBar(context: GraphicsContext, at point: CGPoint, toward target: CGPoint, color: Color) {
        let barWidth: CGFloat = 10
        let angle = atan2(target.y - point.y, target.x - point.x)
        let perpAngle = angle + .pi / 2
        let top = CGPoint(x: point.x + barWidth * cos(perpAngle), y: point.y + barWidth * sin(perpAngle))
        let bottom = CGPoint(x: point.x - barWidth * cos(perpAngle), y: point.y - barWidth * sin(perpAngle))
        var path = Path()
        path.move(to: top); path.addLine(to: bottom)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }
}
