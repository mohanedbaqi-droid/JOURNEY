import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

final class AIPaintRenderer {
    static let shared = AIPaintRenderer()

    private let context = CIContext(options: [.cacheIntermediates: true])
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 48
    }

    func render(base: UIImage, mask: UIImage?, hex: String, key: String) -> UIImage {
        let normalized = hex.uppercased()
        if normalized == "#F2F2F2" || mask == nil { return base }

        let cacheKey = "\(key)|v4|\(normalized)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }

        guard let baseCI = CIImage(image: base),
              let rawMask = CIImage(image: mask!) else { return base }

        let maskCI = rawMask
            .transformed(by: CGAffineTransform(
                scaleX: baseCI.extent.width / max(mask!.size.width, 1),
                y: baseCI.extent.height / max(mask!.size.height, 1)
            ))
            .cropped(to: baseCI.extent)

        let target = UIColor(pdHex: normalized).pdRGBA
        let isBlack = normalized == "#161616"
        let isSilver = normalized == "#A8ADB3"
        let isGray = normalized == "#5C6268"

        // IMPORTANT: only luminance survives from the source paint.
        // Source white/silver RGB is discarded completely inside the body mask.
        let luminance = baseCI
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 1.22,
                kCIInputBrightnessKey: -0.085
            ])
            .applyingFilter("CIGammaAdjust", parameters: [
                "inputPower": isBlack ? 1.08 : 1.02
            ])

        func clamp(_ x: CGFloat) -> CGFloat { min(1.0, max(0.0, x)) }

        let shadowScale: CGFloat = isBlack ? 0.22 : (isGray ? 0.22 : (isSilver ? 0.36 : 0.14))
        let highlightScale: CGFloat = isBlack ? 1.65 : (isGray ? 1.22 : (isSilver ? 1.16 : 1.20))
        let highlightLift: CGFloat = isBlack ? 0.025 : (isSilver ? 0.06 : 0.015)

        let low = CIColor(
            red: clamp(target.r * shadowScale),
            green: clamp(target.g * shadowScale),
            blue: clamp(target.b * shadowScale),
            alpha: 1
        )

        // Highlights stay in the SAME hue family. We do not mix toward white,
        // which is what previously made red look like a red film over a white car.
        let high = CIColor(
            red: clamp(target.r * highlightScale + highlightLift),
            green: clamp(target.g * highlightScale + highlightLift),
            blue: clamp(target.b * highlightScale + highlightLift),
            alpha: 1
        )

        let painted = luminance.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": low,
            "inputColor1": high
        ])

        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = painted
        blend.backgroundImage = baseCI
        blend.maskImage = maskCI

        guard let output = blend.outputImage?.cropped(to: baseCI.extent),
              let cg = context.createCGImage(output, from: baseCI.extent)
        else { return base }

        let result = UIImage(cgImage: cg, scale: base.scale, orientation: base.imageOrientation)
        cache.setObject(result, forKey: cacheKey)
        return result
    }
}

private extension UIColor {
    convenience init(pdHex: String) {
        var value = pdHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1
        )
    }

    var pdRGBA: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r,g,b,a)
    }
}
