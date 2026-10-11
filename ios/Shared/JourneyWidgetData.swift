import Foundation
import Security
#if canImport(WidgetKit)
import WidgetKit
#endif

struct JourneyWidgetSnapshot: Codable, Equatable {
    var demoMode = false
    var deviceID = "journey-esp32s3-01"
    var name = "سيارة جورني"
    var english = false
    var stateAt: Date? = nil
    var obdAt: Date? = nil
    var bodyAt: Date? = nil
    var healthAt: Date? = nil
    var gpsAt: Date? = nil
    var online = false
    var rpm: Int? = nil
    var speed: Int? = nil
    var coolant: Int? = nil
    var fuel: Int? = nil
    var battery: Double? = nil
    var locked: Bool? = nil
    var doorOpenMask = 0
    var doorKnownMask = 0
    var lowBeam: Bool? = nil
    var parking: Bool? = nil
    var leftTurn: Bool? = nil
    var rightTurn: Bool? = nil
    var remotePowered: Bool? = nil
    var obdConnected = false
    var espTemperature: Double? = nil
    var espBattery: Double? = nil
    var firmware = ""
    var latitude: Double? = nil
    var longitude: Double? = nil
    var speedUnit = "kmh"
    var temperatureUnit = "c"
    func text(_ ar: String, _ en: String) -> String { english ? en : ar }
    func door(_ bit: Int) -> Bool? { doorKnownMask & bit == 0 ? nil : doorOpenMask & bit != 0 }
    func fresh(_ date: Date?, at now: Date, seconds: Double) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) >= 0 && now.timeIntervalSince(date) <= seconds
    }
    func expired(at now: Date) -> Self {
        if demoMode { return self }
        var s = self
        s.online = online && fresh(stateAt, at: now, seconds: 12)
        if !s.online || !fresh(obdAt, at: now, seconds: 5) {
            s.rpm = nil; s.speed = nil; s.coolant = nil; s.fuel = nil; s.battery = nil; s.obdConnected = false
        }
        if !s.online || !fresh(bodyAt, at: now, seconds: 5) {
            s.locked = nil; s.doorKnownMask = 0; s.doorOpenMask = 0
            s.lowBeam = nil; s.parking = nil; s.leftTurn = nil; s.rightTurn = nil
        }
        if !s.online || !fresh(healthAt, at: now, seconds: 10) { s.espTemperature = nil; s.espBattery = nil }
        if !s.online || !fresh(gpsAt, at: now, seconds: 12) { s.latitude = nil; s.longitude = nil }
        if !s.online { s.remotePowered = nil }
        return s
    }
    private func key(_ value: Bool?) -> String { value.map { $0 ? "1" : "0" } ?? "?" }
    var importantKey: String {
        "\(demoMode)|\(deviceID)|\(online)|\(key(locked))|\(doorKnownMask)|\(doorOpenMask)|\(key(lowBeam))|\(key(parking))|\(key(leftTurn))|\(key(rightTurn))|\((rpm ?? -1) > 0)"
    }
}

struct JourneyWidgetCommandStatus: Codable {
    var deviceID: String
    var message: String
    var date: Date
}

/// No credentials or owner keys are copied into the widget container.
/// Storage priority: shared App Group file, then a signed shared Keychain
/// access group. Both routes keep the data on-device and require entitlements.
enum JourneyWidgetStore {
    static let declaredGroup = "group.com.abuseif.journey"
    static var groupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: declaredGroup)
    }
    static var available: Bool { groupURL != nil || read() != nil }
    static var keychainSnapshotPresent: Bool {
        JourneyWidgetKeychainBridge.read("snapshot") != nil
    }
    static var sharingMethod: String {
        if groupURL != nil { return "App Group" }
        if keychainSnapshotPresent { return "Keychain" }
        return "Unavailable"
    }

    static func read() -> JourneyWidgetSnapshot? {
        if let url = groupURL?.appendingPathComponent("vehicle.json"),
           let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(JourneyWidgetSnapshot.self, from: data) {
            return snapshot
        }
        guard let data = JourneyWidgetKeychainBridge.read("snapshot") else { return nil }
        return try? JSONDecoder().decode(JourneyWidgetSnapshot.self, from: data)
    }

    @discardableResult static func write(_ snapshot: JourneyWidgetSnapshot, force: Bool = false) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        let previous = read()
        var groupSaved = false
        if let url = groupURL?.appendingPathComponent("vehicle.json") {
            if previous != snapshot || !(FileManager.default.fileExists(atPath: url.path)) {
                groupSaved = (try? data.write(to: url, options: .atomic)) != nil
            } else {
                groupSaved = true
            }
        }

        // Write the same telemetry into the Keychain fallback, independent of
        // whether App Group sharing works. The extension can read the bridge
        // only when SideStore signs both targets with a matching entitlement.
        let keychainSaved: Bool
        if previous != snapshot || force || !keychainSnapshotPresent {
            keychainSaved = JourneyWidgetKeychainBridge.write(data, account: "snapshot")
        } else {
            keychainSaved = true
        }
        guard groupSaved || keychainSaved else { return false }

        let last: Double
        if let reloadURL = groupURL?.appendingPathComponent("reload-date") {
            last = (try? String(contentsOf: reloadURL, encoding: .utf8)).flatMap(Double.init) ?? 0
        } else {
            last = UserDefaults.standard.double(forKey: "journey.widget.lastReload")
        }

        if force || previous?.importantKey != snapshot.importantKey ||
            Date().timeIntervalSince1970 - last > 60 {
            let now = Date().timeIntervalSince1970
            if let reloadURL = groupURL?.appendingPathComponent("reload-date") {
                try? String(now).write(to: reloadURL, atomically: true, encoding: .utf8)
            } else {
                UserDefaults.standard.set(now, forKey: "journey.widget.lastReload")
            }
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: "JourneyHomeWidget")
            #endif
        }
        return true
    }

    static func setStatus(deviceID: String, message: String) {
        guard let data = try? JSONEncoder().encode(
            JourneyWidgetCommandStatus(deviceID: deviceID, message: message, date: Date())
        ) else { return }
        if let url = groupURL?.appendingPathComponent("command.json") {
            try? data.write(to: url, options: .atomic)
        }
        _ = JourneyWidgetKeychainBridge.write(data, account: "command")
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "JourneyHomeWidget")
        #endif
    }

    static func status(deviceID: String, at now: Date) -> String? {
        let data: Data?
        if let url = groupURL?.appendingPathComponent("command.json") {
            data = (try? Data(contentsOf: url)) ??
                JourneyWidgetKeychainBridge.read("command")
        } else {
            data = JourneyWidgetKeychainBridge.read("command")
        }
        guard let data,
              let status = try? JSONDecoder().decode(JourneyWidgetCommandStatus.self, from: data),
              status.deviceID == deviceID,
              now.timeIntervalSince(status.date) >= 0,
              now.timeIntervalSince(status.date) < 30 else { return nil }
        return status.message
    }
}

/// The app and extension use exactly the same Keychain service and account.
/// The bridge never shares MQTT passwords, phone identities, or commands.
/// An access group is taken from the *effective signed entitlements*, since
/// SideStore can replace the build-time Team ID during free-account signing.
private enum JourneyWidgetKeychainBridge {
    private static let service = "com.abuseif.journey.widget.snapshot.v1"
    private static let bridgeSuffix = ".com.abuseif.journey.widgetbridge"

    private static var preferredAccessGroup: String? {
        guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault),
              let value = SecTaskCopyValueForEntitlement(
                task, "keychain-access-groups" as CFString, nil
              ) as? [String] else { return nil }
        return value.first { $0.hasSuffix(bridgeSuffix) }
    }

    private static func query(_ account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    private static var candidates: [String?] {
        // First try the explicit group common to the two targets; if it was
        // stripped during re-signing, the default group may still be common
        // when SideStore uses the main profile for both.
        preferredAccessGroup.map { [$0, nil] } ?? [nil]
    }

    static func read(_ account: String) -> Data? {
        for accessGroup in candidates {
            var request = query(account, accessGroup: accessGroup)
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            if SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data {
                return data
            }
        }
        return nil
    }

    @discardableResult static func write(_ data: Data, account: String) -> Bool {
        for accessGroup in candidates {
            let base = query(account, accessGroup: accessGroup)
            let update: [String: Any] = [kSecValueData as String: data]
            if SecItemUpdate(base as CFDictionary, update as CFDictionary) == errSecSuccess {
                return true
            }
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(add as CFDictionary, nil)
            if result == errSecSuccess { return true }
            if result == errSecDuplicateItem &&
               SecItemUpdate(base as CFDictionary, update as CFDictionary) == errSecSuccess {
                return true
            }
        }
        return false
    }
}
