import Foundation
import Security

enum AppConfig {
    static let cellularCarrier = "Zain Iraq"
    static let cellularAPN = "internet"
    static let defaultBrokerPort: UInt16 = 8883
    static let keychainService = "com.example.JourneyControl.mqtt"
    static let bleServiceUUID = "AF10A000-17B7-4A86-A7D7-9A3B40C8D001"
    /// ESP32 GATT protocol used when the car has no SIM / internet connection.
    static let bleCommandCharacteristicUUID = "AF10A001-17B7-4A86-A7D7-9A3B40C8D001"
    static let bleStateCharacteristicUUID = "AF10A002-17B7-4A86-A7D7-9A3B40C8D001"

    /// Stable app-install identifier enrolled in the ESP on the first keyless save.
    /// iOS does not expose the phone's hardware Bluetooth address.
    static var phoneID: String {
        let account = "journey.owner.phoneID"
        let service = "com.abuseif.journey.owner"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let saved = String(data: data, encoding: .utf8), !saved.isEmpty {
            return saved
        }

        // Preserve the identity used by older builds before moving it to Keychain.
        let legacy = UserDefaults.standard.string(forKey: account)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stable = (legacy?.isEmpty == false) ? legacy! : UUID().uuidString
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(stable.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        SecItemAdd(add as CFDictionary, nil)
        UserDefaults.standard.set(stable, forKey: account)
        return stable
    }

    static let allStateTopics = "journey/+/state"
    static func commandTopic(for deviceID: String) -> String { "journey/\(deviceID)/cmd" }
}
