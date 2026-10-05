import Combine
import Foundation

struct NFCLaunchRequest: Equatable {
    enum Source: String, Equatable {
        case shortcutTag = "iPhone NFC Tag"
        case inAppTest = "In-app test"

        var title: String {
            self == .shortcutTag ? "iPhone NFC Tag" : JL("اختبار داخل التطبيق", "In-app test")
        }
    }

    let source: Source
    let receivedAt: Date
}

@MainActor
final class NFCLaunchRouter: ObservableObject {
    static let shared = NFCLaunchRouter()

    @Published private(set) var pendingRequest: NFCLaunchRequest?

    private init() {}

    @discardableResult
    func route(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "journeycontrol",
              url.host?.lowercased() == "nfc" else {
            return false
        }

        // The tag never contains a vehicle command or secret. It only opens the
        // authenticated flow; Face ID and the secure ESP session decide what happens.
        pendingRequest = NFCLaunchRequest(source: .shortcutTag, receivedAt: Date())
        return true
    }

    func requestInAppTest() {
        pendingRequest = NFCLaunchRequest(source: .inAppTest, receivedAt: Date())
    }

    func consume() -> NFCLaunchRequest? {
        defer { pendingRequest = nil }
        return pendingRequest
    }

    func clear() {
        pendingRequest = nil
    }
}
