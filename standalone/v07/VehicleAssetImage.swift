import SwiftUI
import UIKit

struct VehicleAssetImage: View {
    let profile: VehicleProfile
    let colorHex: String
    var maxHeight: CGFloat = 180
    var plateText: String = ""

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image = UIImage(named: profile.assetKey) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .saturation(0.93)
                        .overlay {
                            Color(hex: colorHex)
                                .opacity(colorHex.uppercased() == "#F2F2F2" ? 0.02 : 0.20)
                                .blendMode(.color)
                                .mask(
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                )
                        }
                        .shadow(color: .black.opacity(0.45), radius: 12, y: 8)

                    if !plateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(plateText)
                            .font(.system(size: max(9, geo.size.width * 0.032), weight: .black, design: .monospaced))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.45)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 3))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.black.opacity(0.7), lineWidth: 0.7))
                            .position(x: geo.size.width * 0.69, y: geo.size.height * 0.72)
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
