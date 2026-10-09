import SwiftUI
import UIKit

struct VehicleAssetImage: View {
    let profile: VehicleProfile
    let colorHex: String
    var maxHeight: CGFloat = 180
    var plateText: String = ""
    var plateShiftX: Double = 0
    var plateShiftY: Double = 0
    var plateScale: Double = 1
    var plateAngleOffset: Double = 0

    @AppStorage("punisher.ai.visual") private var visualAI = true

    private var parsedPlate: (code: String, letter: String, number: String)? {
        IraqPlateData.parse(plateText)
    }

    private var ai: VehicleVisualAIMetadata {
        visualAI ? VehicleVisualAI.shared.metadata(for: profile.assetKey) : .fallback(for: profile.assetKey)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let source = UIImage(named: profile.assetKey) {
                    let mask = UIImage(named: profile.assetKey + "_bodymask")
                    let image = AIPaintRenderer.shared.render(
                        base: source,
                        mask: mask,
                        hex: colorHex,
                        key: profile.assetKey
                    )
                    let rect = fittedRect(imageSize: image.size, in: geo.size)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .shadow(color: .black.opacity(0.46), radius: 12, y: 8)

                    plateOverlay(in: rect)
                } else {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: maxHeight * 0.50, weight: .light))
                        .foregroundStyle(Color(hex: colorHex))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .environment(\.layoutDirection, .leftToRight)
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

    @ViewBuilder
    private func plateOverlay(in imageRect: CGRect) -> some View {
        if let plate = parsedPlate {
            // Auto-detected plate box, with an optional per-vehicle correction.
            let autoWidth = min(imageRect.width * 0.24, max(26, imageRect.width * ai.plateW))
            let width = min(imageRect.width * 0.30, autoWidth * min(1.6, max(0.6, plateScale)))
            let height = width * (31.0 / 140.0)
            let x = min(0.98, max(0.02, ai.plateX + plateShiftX))
            let y = min(0.98, max(0.02, ai.plateY + plateShiftY))

            IraqiPlateView(
                governorateCode: plate.code,
                letter: plate.letter,
                number: plate.number,
                compact: true
            )
            .frame(width: width, height: height)
            .rotationEffect(.degrees(ai.plateAngle + plateAngleOffset))
            .position(
                x: imageRect.minX + imageRect.width * x,
                y: imageRect.minY + imageRect.height * y
            )
            .shadow(color: .black.opacity(0.34), radius: 1, y: 1)
        }
    }
}
