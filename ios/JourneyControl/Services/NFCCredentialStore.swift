import Combine
import Foundation

@MainActor
final class NFCCredentialStore: ObservableObject {
    @Published private(set) var credentials: [NFCCredential] = []
    @Published private(set) var events: [NFCAccessEvent] = []
    @Published var settings = NFCAccessSettings() {
        didSet { saveSettings() }
    }

    private let credentialsKey = "journey.nfc.credentials.v1"
    private let settingsKey = "journey.nfc.settings.v1"
    private let eventsKey = "journey.nfc.events.v1"

    init() {
        let decoder = JSONDecoder()

        if let data = UserDefaults.standard.data(forKey: credentialsKey),
           let saved = try? decoder.decode([NFCCredential].self, from: data) {
            credentials = saved
        }

        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let saved = try? decoder.decode(NFCAccessSettings.self, from: data) {
            settings = saved
        }

        if let data = UserDefaults.standard.data(forKey: eventsKey),
           let saved = try? decoder.decode([NFCAccessEvent].self, from: data) {
            events = saved
        }
    }

    var enabledCredentialCount: Int {
        credentials.filter(\.isEnabled).count
    }

    @discardableResult
    func addBenchCredential(name: String, kind: NFCCredentialKind) -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return JL("اكتب اسماً للبطاقة", "Enter a card name") }

        let randomID = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(14)
            .uppercased()

        credentials.append(
            NFCCredential(
                name: cleanName,
                kind: kind,
                identifier: randomID,
                isBenchCredential: true
            )
        )
        saveCredentials()
        record(
            title: JL("إضافة مفتاح NFC تجريبي", "Add a test NFC key"),
            detail: cleanName,
            result: .bench
        )
        return nil
    }

    func update(_ credential: NFCCredential) {
        guard let index = credentials.firstIndex(where: { $0.id == credential.id }) else { return }
        credentials[index] = credential
        saveCredentials()
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = credentials.firstIndex(where: { $0.id == id }) else { return }
        credentials[index].isEnabled = enabled
        saveCredentials()
    }

    func delete(_ credential: NFCCredential) {
        credentials.removeAll { $0.id == credential.id }
        saveCredentials()
        record(
            title: JL("حذف مفتاح NFC", "Delete NFC key"),
            detail: credential.name,
            result: .bench
        )
    }

    func recordIPhoneLaunch(allowed: Bool, detail: String) {
        record(
            title: allowed ? JL("تم تأكيد مفتاح iPhone", "iPhone key confirmed") : JL("رُفض مفتاح iPhone", "iPhone key rejected"),
            detail: detail,
            result: allowed ? .allowed : .denied
        )
    }

    func record(
        title: String,
        detail: String,
        result: NFCAccessEvent.Result
    ) {
        events.insert(
            NFCAccessEvent(title: title, detail: detail, result: result),
            at: 0
        )
        if events.count > 30 {
            events.removeLast(events.count - 30)
        }
        saveEvents()
    }

    private func saveCredentials() {
        if let data = try? JSONEncoder().encode(credentials) {
            UserDefaults.standard.set(data, forKey: credentialsKey)
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func saveEvents() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: eventsKey)
        }
    }
}
