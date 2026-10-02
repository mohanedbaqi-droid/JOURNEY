import Combine
import Foundation
import UIKit
import UserNotifications

enum HomeScreenShortcut: Equatable {
    case lockPreview
    case unlockPreview
    case startPreview

    init?(shortcutItem: UIApplicationShortcutItem) {
        switch shortcutItem.type {
        case "com.example.JourneyControlBench.preview.lock":
            self = .lockPreview
        case "com.example.JourneyControlBench.preview.unlock":
            self = .unlockPreview
        default:
            return nil
        }
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "journeycontrol",
              url.host?.lowercased() == "widget" else { return nil }

        switch url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() {
        case "lock": self = .lockPreview
        case "unlock": self = .unlockPreview
        case "start": self = .startPreview
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .lockPreview: return "قفل السيارة"
        case .unlockPreview: return "فتح السيارة"
        case .startPreview: return "تشغيل السيارة"
        }
    }

    var action: BenchAction {
        switch self {
        case .lockPreview: return .lock
        case .unlockPreview: return .unlock
        case .startPreview: return .start
        }
    }
}

final class HomeScreenShortcutRouter: ObservableObject {
    static let shared = HomeScreenShortcutRouter()

    @Published private(set) var pendingShortcut: HomeScreenShortcut?

    private init() {}

    @discardableResult
    func route(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let shortcut = HomeScreenShortcut(shortcutItem: shortcutItem) else { return false }
        pendingShortcut = shortcut
        return true
    }

    @discardableResult
    func route(_ url: URL) -> Bool {
        guard let shortcut = HomeScreenShortcut(url: url) else { return false }
        pendingShortcut = shortcut
        return true
    }

    func consume() -> HomeScreenShortcut? {
        defer { pendingShortcut = nil }
        return pendingShortcut
    }

    func clear() {
        pendingShortcut = nil
    }
}

final class JourneyControlAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            DispatchQueue.main.async {
                _ = HomeScreenShortcutRouter.shared.route(shortcutItem)
            }
        }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async {
            completionHandler(HomeScreenShortcutRouter.shared.route(shortcutItem))
        }
    }
}
