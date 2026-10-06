import Foundation
import CoreGraphics

struct VehicleVisualAIMetadata: Codable, Hashable {
    let assetKey: String
    let plateX: Double
    let plateY: Double
    let plateW: Double
    let plateH: Double
    let plateAngle: Double
    let colorStrength: Double
    let confidence: Double

    static func fallback(for assetKey: String) -> VehicleVisualAIMetadata {
        VehicleVisualAIMetadata(
            assetKey: assetKey,
            plateX: 0.70,
            plateY: 0.705,
            plateW: 0.235,
            plateH: 0.105,
            plateAngle: -1.5,
            colorStrength: 0.72,
            confidence: 0.25
        )
    }
}

final class VehicleVisualAI {
    static let shared = VehicleVisualAI()

    private var values: [String: VehicleVisualAIMetadata] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "vehicle_visual_ai", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([VehicleVisualAIMetadata].self, from: data)
        else { return }

        values = Dictionary(uniqueKeysWithValues: list.map { ($0.assetKey, $0) })
    }

    func metadata(for assetKey: String) -> VehicleVisualAIMetadata {
        values[assetKey] ?? .fallback(for: assetKey)
    }
}
