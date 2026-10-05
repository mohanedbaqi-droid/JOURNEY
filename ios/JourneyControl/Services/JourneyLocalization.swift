import Foundation

/// The app language is independent of the iPhone system language.
/// Resolve at presentation time so every view and newly generated message uses
/// the same preference as the language picker.
func JL(_ arabic: String, _ english: String) -> String {
    UserDefaults.standard.string(forKey: "journey.settings.language") == "en"
        ? english : arabic
}
