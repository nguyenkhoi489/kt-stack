import CoreGraphics
import Foundation

public enum ERPositionStore {
    private static let defaults = UserDefaults.standard

    private static func key(connectionKey: String, schemaKey: String) -> String {
        "com.ktstack.erDiagram.positions.\(connectionKey).\(schemaKey)"
    }

    public static func load(connectionKey: String, schemaKey: String) -> [String: CGPoint] {
        guard let data = defaults.data(forKey: key(connectionKey: connectionKey, schemaKey: schemaKey)),
              let stored = try? JSONDecoder().decode([String: StoredPoint].self, from: data)
        else { return [:] }
        return stored.mapValues { CGPoint(x: $0.x, y: $0.y) }
    }

    public static func save(_ positions: [String: CGPoint], connectionKey: String, schemaKey: String) {
        let stored = positions.mapValues { StoredPoint(x: $0.x, y: $0.y) }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key(connectionKey: connectionKey, schemaKey: schemaKey))
    }

    public static func clear(connectionKey: String, schemaKey: String) {
        defaults.removeObject(forKey: key(connectionKey: connectionKey, schemaKey: schemaKey))
    }

    private struct StoredPoint: Codable {
        let x: Double
        let y: Double
    }
}
