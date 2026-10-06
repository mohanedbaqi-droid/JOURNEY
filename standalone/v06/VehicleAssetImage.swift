import SwiftUI
import UIKit

struct VehicleAssetImage: View {
    let profile: VehicleProfile
    let colorHex: String
    var maxHeight: CGFloat = 120

    var body: some View {
        Group {
            if let image = UIImage(named: profile.assetKey) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
                    .saturation(0.72)
                    .colorMultiply(Color(hex: colorHex))
                    .shadow(color: Color(hex: colorHex).opacity(0.18), radius: 10, y: 4)
            } else {
                Image(systemName: "car.side.fill")
                    .font(.system(size: maxHeight * 0.58, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(hex: colorHex))
            }
        }
        .accessibilityLabel("\(profile.make) \(profile.model)")
    }
}
