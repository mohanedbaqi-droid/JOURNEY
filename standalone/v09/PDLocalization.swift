import SwiftUI

enum PDLanguage: String, CaseIterable, Identifiable {
    case ar
    case en

    var id: String { rawValue }
    var label: String { self == .ar ? "العربية" : "English" }
}

enum PDLocalization {
    static let key = "punisher.language"

    static var current: PDLanguage {
        PDLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "ar") ?? .ar
    }

    static var isEnglish: Bool { current == .en }
}

func pd(_ ar: String, _ en: String) -> String {
    PDLocalization.isEnglish ? en : ar
}
