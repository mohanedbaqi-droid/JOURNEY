import SwiftUI
import UIKit

struct VehicleAssetImage: View {
    let profile: VehicleProfile
    let colorHex: String
    var maxHeight: CGFloat = 180
    var plateText: String = ""

    @AppStorage("punisher.ai.visual") private var visualAI = true
    @AppStorage("punisher.ai.plate") private var autoPlate = true
    @AppStorage("punisher.ai.color") private var smartColor = true

    private var parsedPlate: (code: String, letter: String, number: String)? {
        IraqPlateData.parse(plateText)
    }

    private var ai: VehicleVisualAIMetadata {
        visualAI ? VehicleVisualAI.shared.metadata(for: profile.assetKey) : .fallback(for: profile.assetKey)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = UIImage(named: profile.assetKey) {
                    baseVehicle(image)
                    bodyColorOverlay(image)
                    plateOverlay(in: geo.size)
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

    private func baseVehicle(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .saturation(colorHex.uppercased() == "#F2F2F2" ? 1.0 : 0.86)
            .shadow(color: .black.opacity(0.46), radius: 12, y: 8)
    }

    @ViewBuilder
    private func bodyColorOverlay(_ image: UIImage) -> some View {
        if colorHex.uppercased() != "#F2F2F2" {
            let strength = smartColor ? ai.colorStrength : 0.50
            Color(hex: colorHex)
                .opacity(colorHex.uppercased() == "#161616" ? min(0.92, strength + 0.12) : strength)
                .blendMode(colorHex.uppercased() == "#161616" ? .multiply : .color)
                .mask {
                    if smartColor, let mask = UIImage(named: profile.assetKey + "_bodymask") {
                        Image(uiImage: mask)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .grayscale(1)
                            .contrast(1.45)
                            .luminanceToAlpha()
                    }
                }
        }
    }

    @ViewBuilder
    private func plateOverlay(in size: CGSize) -> some View {
        if let plate = parsedPlate {
            let px = autoPlate ? ai.plateX : 0.70
            let py = autoPlate ? ai.plateY : 0.705
            let pw = autoPlate ? ai.plateW : 0.235
            let ph = autoPlate ? ai.plateH : 0.105
            let angle = autoPlate ? ai.plateAngle : -1.5

            IraqiPlateView(
                governorateCode: plate.code,
                letter: plate.letter,
                number: plate.number,
                compact: true
            )
            .frame(width: max(60, size.width * pw), height: max(16, size.height * ph))
            .rotationEffect(.degrees(angle))
            .position(
                x: size.width * px,
                y: size.height * py
            )
            .shadow(color: .black.opacity(0.30), radius: 1, y: 1)
        }
    }
}
