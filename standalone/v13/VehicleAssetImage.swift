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
                    let rect = fittedRect(imageSize: image.size, in: geo.size)
                    baseVehicle(image)
                    bodyColorOverlay(image)
                    plateOverlay(in: rect)
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

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func baseVehicle(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .saturation(colorHex.uppercased() == "#F2F2F2" ? 1.0 : 0.68)
            .contrast(colorHex.uppercased() == "#F2F2F2" ? 1.0 : 1.04)
            .shadow(color: .black.opacity(0.46), radius: 12, y: 8)
    }

    @ViewBuilder
    private func bodyColorOverlay(_ image: UIImage) -> some View {
        if colorHex.uppercased() != "#F2F2F2" {
            let strength = smartColor ? max(0.82, ai.colorStrength) : 0.80
            let target = Color(hex: colorHex)

            target
                .opacity(colorHex.uppercased() == "#161616" ? 0.94 : min(0.96, strength))
                .blendMode(.multiply)
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
                            .contrast(1.55)
                            .luminanceToAlpha()
                    }
                }

            // Restore a little highlight so paint keeps the original panel reflections.
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .grayscale(1)
                .brightness(0.10)
                .contrast(1.25)
                .opacity(colorHex.uppercased() == "#161616" ? 0.10 : 0.16)
                .blendMode(.screen)
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
                            .luminanceToAlpha()
                    }
                }
        }
    }

    @ViewBuilder
    private func plateOverlay(in imageRect: CGRect) -> some View {
        if let plate = parsedPlate {
            let px = ai.plateX
            let py = ai.plateY
            let pw = max(ai.plateW, 0.235)
            let ph = max(ai.plateH, 0.080)
            let angle = ai.plateAngle

            IraqiPlateView(
                governorateCode: plate.code,
                letter: plate.letter,
                number: plate.number,
                compact: true
            )
            .frame(
                width: max(92, imageRect.width * pw),
                height: max(22, imageRect.height * ph)
            )
            .rotationEffect(.degrees(angle))
            .position(
                x: imageRect.minX + imageRect.width * px,
                y: imageRect.minY + imageRect.height * py
            )
            .shadow(color: .black.opacity(0.34), radius: 1, y: 1)
        }
    }
}
