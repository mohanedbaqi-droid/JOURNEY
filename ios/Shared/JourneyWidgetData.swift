import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct JourneyWidgetSnapshot: Codable, Equatable {
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
        "\(deviceID)|\(online)|\(key(locked))|\(doorKnownMask)|\(doorOpenMask)|\(key(lowBeam))|\(key(parking))|\(key(leftTurn))|\(key(rightTurn))|\((rpm ?? -1) > 0)"
    }
}

struct JourneyWidgetCommandStatus: Codable {
    var deviceID: String
    var message: String
    var date: Date
}

/// No credentials or owner keys are copied into the widget container.
enum JourneyWidgetStore {
    static let declaredGroup = "group.com.abuseif.journey"
    static var groupURL: URL? {
        // Query the effective entitlement through the system instead of parsing
        // embedded.mobileprovision. Sideloaders can re-sign the extension without
        // bundling that profile, even when its App Group entitlement is valid.
        // A missing entitlement returns nil, allowing the widget to show offline.
        return FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: declaredGroup
        )
    }
    static var available: Bool { groupURL != nil }
    static func read() -> JourneyWidgetSnapshot? {
        guard let url = groupURL?.appendingPathComponent("vehicle.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(JourneyWidgetSnapshot.self, from: data)
    }
    @discardableResult static func write(_ snapshot: JourneyWidgetSnapshot, force: Bool = false) -> Bool {
        guard let url = groupURL?.appendingPathComponent("vehicle.json"), let data = try? JSONEncoder().encode(snapshot) else { return false }
        let previous = read()
        if previous != snapshot { do { try data.write(to: url, options: .atomic) } catch { return false } }
        let reloadURL = url.deletingLastPathComponent().appendingPathComponent("reload-date")
        let last = (try? String(contentsOf: reloadURL, encoding: .utf8)).flatMap(Double.init) ?? 0
        if force || previous?.importantKey != snapshot.importantKey || Date().timeIntervalSince1970 - last > 60 {
            try? String(Date().timeIntervalSince1970).write(to: reloadURL, atomically: true, encoding: .utf8)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: "JourneyHomeWidget")
            #endif
        }
        return true
    }
    static func setStatus(deviceID: String, message: String) {
        guard let url = groupURL?.appendingPathComponent("command.json"),
              let data = try? JSONEncoder().encode(JourneyWidgetCommandStatus(deviceID: deviceID, message: message, date: Date())) else { return }
        try? data.write(to: url, options: .atomic)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "JourneyHomeWidget")
        #endif
    }
    static func status(deviceID: String, at now: Date) -> String? {
        guard let url = groupURL?.appendingPathComponent("command.json"), let data = try? Data(contentsOf: url),
              let status = try? JSONDecoder().decode(JourneyWidgetCommandStatus.self, from: data), status.deviceID == deviceID,
              now.timeIntervalSince(status.date) >= 0, now.timeIntervalSince(status.date) < 30 else { return nil }
        return status.message
    }
}
