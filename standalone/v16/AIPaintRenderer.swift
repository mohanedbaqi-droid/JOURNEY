import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

final class AIPaintRenderer {
    static let shared = AIPaintRenderer()

    private let context = CIContext(options: [.cacheIntermediates: true])
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 40
    }

    func render(base: UIImage, mask: UIImage?, hex: String, key: String) -> UIImage {
        let normalized = hex.uppercased()
        if normalized == "#F2F2F2" || mask == nil { return base }

        let cacheKey = "\(key)|\(normalized)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }

        guard let baseCI = CIImage(image: base),
              let maskCI = CIImage(image: mask!)?.transformed(
                by: CGAffineTransform(
                    scaleX: baseCI.extent.width / max(mask!.size.width, 1),
                    y: baseCI.extent.height / max(mask!.size.height, 1)
                )
              ).cropped(to: baseCI.extent)
        else { return base }

        let target = UIColor(pdHex: normalized)
        let components = target.pdRGBA
        let r = components.r, g = components.g, b = components.b

        let gray = baseCI
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 1.14,
                kCIInputBrightnessKey: -0.015
            ])
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.92])

        let isBlack = normalized == "#161616"
        let isSilver = normalized == "#A8ADB3" || normalized == "#5C6268"

        let darkScale: CGFloat = isBlack ? 0.035 : (isSilver ? 0.20 : 0.13)
        let highlightMix: CGFloat = isBlack ? 0.34 : (isSilver ? 0.52 : 0.36)

        let dark = CIColor(
            red: r * darkScale,
            green: g * darkScale,
            blue: b * darkScale,
            alpha: 1
        )
        let high = CIColor(
            red: r + (1-r) * highlightMix,
            green: g + (1-g) * highlightMix,
            blue: b + (1-b) * highlightMix,
            alpha: 1
        )

        let painted = gray.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": dark,
            "inputColor1": high
        ])

        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = painted
        blend.backgroundImage = baseCI
        blend.maskImage = maskCI

        guard let output = blend.outputImage?.cropped(to: baseCI.extent),
              let cg = context.createCGImage(output, from: baseCI.extent)
        else { return base }

        let rendered = UIImage(cgImage: cg, scale: base.scale, orientation: base.imageOrientation)
        cache.setObject(rendered, forKey: cacheKey)
        return rendered
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
