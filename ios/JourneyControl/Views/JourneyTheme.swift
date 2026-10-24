import SwiftUI
import UIKit

enum JourneyTheme {
    static let ink = Color(uiColor: .label)
    static let surface = Color(uiColor: .systemBackground)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .light
            ? UIColor(red: 0, green: 0.36, blue: 0.48, alpha: 1)
            : UIColor.systemCyan
    })
}

/// Uses the native iOS 26 Liquid Glass surface where available, with a
/// system-material fallback on earlier iOS releases.
extension View {
    @ViewBuilder
    func journeyLiquidGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
