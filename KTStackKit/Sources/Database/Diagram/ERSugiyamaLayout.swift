import CoreGraphics
import Foundation

public enum ERSugiyamaLayout {
    public static let nodeWidth: CGFloat = 220
    public static let headerHeight: CGFloat = 34
    public static let columnRowHeight: CGFloat = 22
    public static let horizontalGap: CGFloat = 60
    public static let verticalGap: CGFloat = 40
    public static let padding: CGFloat = 40

    public static func estimateHeight(columnCount: Int) -> CGFloat {
        headerHeight + CGFloat(max(columnCount, 1)) * columnRowHeight
    }

    public static func compute(graph: ERSchemaGraph) -> [String: CGPoint] {
        guard !graph.nodes.isEmpty else { return [:] }
        let nodeIds = graph.nodes.map(\.id)
        let adjacency = buildAdjacency(graph: graph, nodeIds: nodeIds)
        let dagEdges = breakCycles(adjacency: adjacency, nodeIds: nodeIds)
        let layers = assignLayers(dagEdges: dagEdges, nodeIds: nodeIds)
        let ordered = minimizeCrossings(layers: layers, dagEdges: dagEdges)
        return assignCoordinates(orderedLayers: ordered, graph: graph)
    }

    private static func buildAdjacency(graph: ERSchemaGraph, nodeIds: [String]) -> [String: [String]] {
        var adjacency: [String: [String]] = [:]
        for id in nodeIds {
            adjacency[id] = []
        }
        for edge in graph.edges {
            guard adjacency[edge.fromTable] != nil, adjacency[edge.toTable] != nil else { continue }
            adjacency[edge.fromTable, default: []].append(edge.toTable)
        }
        return adjacency
    }

    private static func breakCycles(adjacency: [String: [String]], nodeIds: [String]) -> [String: [String]] {
        var visited: Set<String> = []
        var onStack: Set<String> = []
        var dag = adjacency
        var backEdges: [(String, String)] = []

        for startNode in nodeIds where !visited.contains(startNode) {
            var stack: [(node: String, idx: Int)] = [(startNode, 0)]
            visited.insert(startNode)
            onStack.insert(startNode)

            while !stack.isEmpty {
                let (node, idx) = stack[stack.count - 1]
                let neighbors = adjacency[node] ?? []
                if idx < neighbors.count {
                    stack[stack.count - 1].idx += 1
                    let neighbor = neighbors[idx]
                    if onStack.contains(neighbor) {
                        backEdges.append((node, neighbor))
                    } else if !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        onStack.insert(neighbor)
                        stack.append((neighbor, 0))
                    }
                } else {
                    onStack.remove(node)
                    stack.removeLast()
                }
            }
        }

        for (from, to) in backEdges {
            dag[from]?.removeAll { $0 == to }
        }
        return dag
    }

    private static func assignLayers(dagEdges: [String: [String]], nodeIds: [String]) -> [[String]] {
        var inDegree: [String: Int] = [:]
        for id in nodeIds {
            inDegree[id] = 0
        }
        for (_, neighbors) in dagEdges {
            for neighbor in neighbors {
                inDegree[neighbor, default: 0] += 1
            }
        }

        var queue = nodeIds.filter { (inDegree[$0] ?? 0) == 0 }
        var layerAssignment: [String: Int] = [:]
        for id in queue {
            layerAssignment[id] = 0
        }

        var idx = 0
        while idx < queue.count {
            let node = queue[idx]
            idx += 1
            let currentLayer = layerAssignment[node] ?? 0
            for neighbor in dagEdges[node] ?? [] {
                let newLayer = currentLayer + 1
                if newLayer > (layerAssignment[neighbor] ?? 0) {
                    layerAssignment[neighbor] = newLayer
                }
                inDegree[neighbor] = (inDegree[neighbor] ?? 1) - 1
                if inDegree[neighbor] == 0 {
                    queue.append(neighbor)
                }
            }
        }

        for id in nodeIds where layerAssignment[id] == nil {
            layerAssignment[id] = 0
        }

        var layers: [Int: [String]] = [:]
        for id in nodeIds {
            let layer = layerAssignment[id] ?? 0
            layers[layer, default: []].append(id)
        }
        let maxLayer = layers.keys.max() ?? 0
        return (0...maxLayer).map { layers[$0] ?? [] }
    }

    private static func minimizeCrossings(layers: [[String]], dagEdges: [String: [String]]) -> [[String]] {
        guard layers.count > 1 else { return layers }

        var reverseEdges: [String: [String]] = [:]
        for (from, neighbors) in dagEdges {
            for to in neighbors {
                reverseEdges[to, default: []].append(from)
            }
        }

        var result = layers
        let sweepCount = min(layers.count * 2, 8)

        for sweep in 0..<sweepCount {
            if sweep.isMultiple(of: 2) {
                for layerIdx in 1..<result.count {
                    let upperPositions = Dictionary(
                        uniqueKeysWithValues: result[layerIdx - 1].enumerated().map { ($1, $0) }
                    )
                    var barycenters: [String: Double] = [:]
                    for node in result[layerIdx] {
                        let positions = (reverseEdges[node] ?? []).compactMap { upperPositions[$0] }
                        if !positions.isEmpty {
                            barycenters[node] = Double(positions.reduce(0, +)) / Double(positions.count)
                        }
                    }
                    result[layerIdx] = stableSort(result[layerIdx], by: barycenters)
                }
            } else {
                for layerIdx in stride(from: result.count - 2, through: 0, by: -1) {
                    let lowerPositions = Dictionary(
                        uniqueKeysWithValues: result[layerIdx + 1].enumerated().map { ($1, $0) }
                    )
                    var barycenters: [String: Double] = [:]
                    for node in result[layerIdx] {
                        let positions = (dagEdges[node] ?? []).compactMap { lowerPositions[$0] }
                        if !positions.isEmpty {
                            barycenters[node] = Double(positions.reduce(0, +)) / Double(positions.count)
                        }
                    }
                    result[layerIdx] = stableSort(result[layerIdx], by: barycenters)
                }
            }
        }
        return result
    }

    private static func stableSort(_ nodes: [String], by barycenters: [String: Double]) -> [String] {
        nodes.enumerated().sorted { lhs, rhs in
            let lb = barycenters[lhs.element] ?? .infinity
            let rb = barycenters[rhs.element] ?? .infinity
            if lb != rb { return lb < rb }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func assignCoordinates(orderedLayers: [[String]], graph: ERSchemaGraph) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]
        let columnCountByTable = Dictionary(
            uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.displayColumns.count) }
        )
        let connected = graph.connectedTables

        var connectedLayers: [[String]] = []
        var isolatedNodes: [String] = []
        for layer in orderedLayers {
            var layerConnected: [String] = []
            for nodeId in layer {
                if connected.contains(nodeId) {
                    layerConnected.append(nodeId)
                } else {
                    isolatedNodes.append(nodeId)
                }
            }
            if !layerConnected.isEmpty { connectedLayers.append(layerConnected) }
        }

        var currentY: CGFloat = padding
        let totalConnectedNodes = connectedLayers.reduce(0) { $0 + $1.count }

        for layer in connectedLayers {
            let layerWidth = CGFloat(layer.count) * nodeWidth + CGFloat(max(layer.count - 1, 0)) * horizontalGap
            let totalWidth = max(layerWidth, CGFloat(totalConnectedNodes) * (nodeWidth + horizontalGap))
            var currentX = padding + nodeWidth / 2 + (totalWidth - layerWidth) / 2
            var maxHeight: CGFloat = 0
            for nodeId in layer {
                let height = estimateHeight(columnCount: columnCountByTable[nodeId] ?? 1)
                positions[nodeId] = CGPoint(x: currentX, y: currentY + height / 2)
                currentX += nodeWidth + horizontalGap
                maxHeight = max(maxHeight, height)
            }
            currentY += maxHeight + verticalGap
        }

        if !isolatedNodes.isEmpty {
            currentY += verticalGap
            let gridColumns = max(Int(Double(isolatedNodes.count).squareRoot()), 3)
            var col = 0
            var rowMaxHeight: CGFloat = 0
            for nodeId in isolatedNodes.sorted() {
                let height = estimateHeight(columnCount: columnCountByTable[nodeId] ?? 1)
                let x = padding + nodeWidth / 2 + CGFloat(col) * (nodeWidth + horizontalGap)
                positions[nodeId] = CGPoint(x: x, y: currentY + height / 2)
                rowMaxHeight = max(rowMaxHeight, height)
                col += 1
                if col >= gridColumns {
                    col = 0
                    currentY += rowMaxHeight + verticalGap
                    rowMaxHeight = 0
                }
            }
        }

        return positions
    }
}

public enum ERRectIndex {
    public static func rects(positions: [String: CGPoint], nodes: [ERSchemaNode]) -> [String: CGRect] {
        var rects: [String: CGRect] = [:]
        for node in nodes {
            guard let center = positions[node.id] else { continue }
            let height = ERSugiyamaLayout.estimateHeight(columnCount: node.displayColumns.count)
            rects[node.id] = CGRect(
                x: center.x - ERSugiyamaLayout.nodeWidth / 2,
                y: center.y - height / 2,
                width: ERSugiyamaLayout.nodeWidth,
                height: height
            )
        }
        return rects
    }

    public static func canvasSize(rects: [String: CGRect]) -> CGSize {
        guard !rects.isEmpty else { return CGSize(width: 800, height: 600) }
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for rect in rects.values {
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }
        return CGSize(width: maxX + ERSugiyamaLayout.padding, height: maxY + ERSugiyamaLayout.padding)
    }
}
