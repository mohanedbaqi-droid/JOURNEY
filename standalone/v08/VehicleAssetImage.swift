import SwiftUI
import UIKit

struct VehicleAssetImage: View {
    let profile: VehicleProfile
    let colorHex: String
    var maxHeight: CGFloat = 180
    var plateText: String = ""

    private var parsedPlate: (code: String, letter: String, number: String)? {
        IraqPlateData.parse(plateText)
    }

    private var plateAnchor: CGPoint {
        let name = "\(profile.make) \(profile.model)".lowercased()
        if name.contains("silverado") || name.contains("sierra") || name.contains("ram") || name.contains("f-150") || name.contains("pickup") {
            return CGPoint(x: 0.70, y: 0.70)
        }
        if name.contains("land cruiser") || name.contains("tahoe") || name.contains("yukon") || name.contains("patrol") || name.contains("prado") || name.contains("rav4") || name.contains("journey") {
            return CGPoint(x: 0.69, y: 0.695)
        }
        return CGPoint(x: 0.70, y: 0.705)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = UIImage(named: profile.assetKey) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .saturation(colorHex.uppercased() == "#F2F2F2" ? 1.0 : 0.72)
                        .overlay {
                            if colorHex.uppercased() != "#F2F2F2" {
                                Color(hex: colorHex)
                                    .opacity(colorHex.uppercased() == "#161616" ? 0.78 : 0.72)
                                    .blendMode(colorHex.uppercased() == "#161616" ? .multiply : .color)
                                    .mask(
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .grayscale(1)
                                            .contrast(1.55)
                                            .luminanceToAlpha()
                                    )
                            }
                        }
                        .shadow(color: .black.opacity(0.45), radius: 12, y: 8)

                    if let plate = parsedPlate {
                        IraqiPlateView(
                            governorateCode: plate.code,
                            letter: plate.letter,
                            number: plate.number,
                            compact: true
                        )
                        .frame(width: max(62, geo.size.width * 0.235), height: max(18, geo.size.height * 0.105))
                        .rotationEffect(.degrees(-1.5))
                        .position(
                            x: geo.size.width * plateAnchor.x,
                            y: geo.size.height * plateAnchor.y
                        )
                        .shadow(color: .black.opacity(0.28), radius: 1, y: 1)
                    }
                } else {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: maxHeight * 0.50, weight: .light))
                        .foregroundStyle(Color(hex: colorHex))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: maxHeight)
        .accessibilityLabel("\(profile.make) \(profile.model)")
    }
}
