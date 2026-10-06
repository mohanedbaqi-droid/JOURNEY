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
