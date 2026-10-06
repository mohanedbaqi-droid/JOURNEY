import SwiftUI

enum PDLanguage: String, CaseIterable, Identifiable {
    case ar
    case en
    case ku
    case tr
    case fa

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ar: return "العربية"
        case .en: return "English"
        case .ku: return "کوردی (سۆرانی)"
        case .tr: return "Türkçe"
        case .fa: return "فارسی"
        }
    }

    var shortLabel: String {
        switch self {
        case .ar: return "AR"
        case .en: return "EN"
        case .ku: return "KU"
        case .tr: return "TR"
        case .fa: return "FA"
        }
    }

    var isRTL: Bool {
        self == .ar || self == .ku || self == .fa
    }
}

enum PDLocalization {
    static let key = "punisher.language"

    static var current: PDLanguage {
        PDLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "ar") ?? .ar
    }

    static var layoutDirection: LayoutDirection {
        current.isRTL ? .rightToLeft : .leftToRight
    }
}

func pd(_ ar: String, _ en: String) -> String {
    switch PDLocalization.current {
    case .ar: return ar
    case .en: return en
    case .ku: return en
    case .tr: return en
    case .fa: return en
    }
}

func pd(_ ar: String, _ en: String, _ ku: String, _ tr: String, _ fa: String) -> String {
    switch PDLocalization.current {
    case .ar: return ar
    case .en: return en
    case .ku: return ku
    case .tr: return tr
    case .fa: return fa
    }
}
