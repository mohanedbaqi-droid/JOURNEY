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
    let frontSide: String?

    static func fallback(for assetKey: String) -> VehicleVisualAIMetadata {
        VehicleVisualAIMetadata(
            assetKey: assetKey,
            plateX: 0.30,
            plateY: 0.68,
            plateW: 0.18,
            plateH: 0.070,
            plateAngle: 0,
            colorStrength: 0.92,
            confidence: 0.20,
            frontSide: nil
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
