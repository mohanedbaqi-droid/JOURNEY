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

/// Uses Apple's native Liquid Glass on SDKs that provide it, and falls back
/// to system material when building with an older Xcode/SwiftUI SDK.
extension View {
    @ViewBuilder
    func journeyLiquidGlass<S: Shape>(in shape: S) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
#else
        self.background(.ultraThinMaterial, in: shape)
#endif
    }
}
