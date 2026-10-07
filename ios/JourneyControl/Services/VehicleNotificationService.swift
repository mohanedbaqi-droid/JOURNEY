import Foundation
import UserNotifications

/// Sends one concise local notification for meaningful vehicle-state changes.
/// MQTT remains the source of truth: a command is only announced after the ESP
/// publishes the updated state back to the app.
@MainActor
final class VehicleNotificationService {
    static let shared = VehicleNotificationService()

    private let defaults = UserDefaults.standard
    private let proximityNearKey = "journey.notification.proximity.near"

    private init() {}

    private func settingEnabled(_ key: String, default defaultValue: Bool) -> Bool {
        if defaults.object(forKey: key) == nil { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private var engineNotificationsEnabled: Bool { settingEnabled("journey.settings.notifyEngine", default: true) }
    private var keylessNotificationsEnabled: Bool { settingEnabled("journey.settings.notifyKeyless", default: true) }
    private var lockNotificationsEnabled: Bool { settingEnabled("journey.settings.notifyLocks", default: true) }
    private var obdNotificationsEnabled: Bool { settingEnabled("journey.settings.notifyOBD", default: false) }

    private func eventAllowed(_ type: String) -> Bool {
        if type.hasPrefix("engine_") { return engineNotificationsEnabled }
        if type.hasPrefix("keyless_presence") { return keylessNotificationsEnabled }
        if type.hasPrefix("keyless_lock") || type == "keyless_unlock" { return lockNotificationsEnabled }
        if type.hasPrefix("obd_") { return obdNotificationsEnabled }
        return true
    }

    @discardableResult
    func notifyVehicleEvent(id: String, type: String, text: String, vehicleName: String) -> Bool {
        guard !id.isEmpty, eventAllowed(type) else { return false }
        let key = "journey.vehicle.event.delivered.\(id)"
        if defaults.bool(forKey: key) { return true }

        if type == "keyless_presence_near" {
            if defaults.bool(forKey: proximityNearKey) {
                defaults.set(true, forKey: key)
                return true
            }
            defaults.set(true, forKey: proximityNearKey)
        } else if type == "keyless_presence_far" {
            if !defaults.bool(forKey: proximityNearKey) {
                defaults.set(true, forKey: key)
                return true
            }
            defaults.set(false, forKey: proximityNearKey)
        }

        let content = UNMutableNotificationContent()
        content.title = vehicleName
        content.body = type.hasPrefix("esp_temperature_") || text.isEmpty ? eventText(for: type) : text
        content.sound = .default
        content.threadIdentifier = "journey.vehicle.events"
        content.categoryIdentifier = "JOURNEY_VEHICLE"
        let request = UNNotificationRequest(identifier: "journey.event.\(id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        defaults.set(true, forKey: key)
        return true
    }

    private func eventText(for type: String) -> String {
        switch type {
        case "engine_started_obd": return JL("تم تشغيل السيارة", "Engine started")
        case "engine_stopped_obd": return JL("تم إطفاء السيارة", "Engine stopped")
        case "esp_temperature_high": return JL("تنبيه: حرارة شريحة ESP مرتفعة — افحص التهوية", "Warning: high ESP chip temperature — check ventilation")
        case "esp_temperature_critical": return JL("تحذير: حرارة شريحة ESP مرتفعة جداً — افحص التهوية والتغذية", "Warning: very high ESP chip temperature — check ventilation and power")
        case "coolant_high": return JL("تحذير: حرارة المحرك مرتفعة", "Warning: high engine temperature")
        case "battery_low": return JL("تحذير: فولت بطارية السيارة منخفض", "Warning: low vehicle battery voltage")
        case "keyless_presence_near": return JL("اقتربت من السيارة — تم اكتشاف الهاتف", "Approaching vehicle — phone detected")
        case "keyless_presence_far": return JL("ابتعدت عن السيارة — خرج الهاتف من نطاق القرب", "Leaving vehicle — phone outside proximity range")
        case "keyless_unlock": return JL("اقتربت من السيارة — تم فتح السيارة", "Approaching vehicle — vehicle unlocked")
        case "keyless_lock", "keyless_lock_departure": return JL("ابتعدت عن السيارة — تم قفل السيارة", "Leaving vehicle — vehicle locked")
        default: return JL("يوجد تحديث جديد من السيارة", "New vehicle update")
        }
    }

    func notifyChanges(from old: VehicleState?, to new: VehicleState, vehicleName: String) {
        // The first packet only establishes the baseline; it is not an event.
        guard let old else { return }

        var changes: [String] = []
        // v12.51: notify on the actual proximity transition even when lock state
        // does not change (for example manual-lock latch or remote already on).
        if keylessNotificationsEnabled && old.lastEvent != new.lastEvent {
            if new.lastEvent == "keyless_presence_near" {
                changes.append(JL("اقتربت من السيارة — تم اكتشاف الهاتف", "Approaching vehicle — phone detected"))
            } else if new.lastEvent == "keyless_presence_far" {
                changes.append(JL("ابتعدت عن السيارة — خرج الهاتف من نطاق القرب", "Leaving vehicle — phone outside proximity range"))
            }
        }
        if lockNotificationsEnabled && old.simulatedLocked != new.simulatedLocked {
            if new.lastEvent == "keyless_unlock" {
                changes.append(JL("اقتربت من السيارة — تم فتح السيارة", "Approaching vehicle — vehicle unlocked"))
            } else if new.lastEvent == "keyless_lock_departure" || new.lastEvent == "keyless_lock" {
                changes.append(JL("ابتعدت عن السيارة — تم قفل السيارة", "Leaving vehicle — vehicle locked"))
            } else {
                changes.append(new.simulatedLocked ? JL("تم قفل السيارة", "Vehicle locked") : JL("تم فتح السيارة", "Vehicle unlocked"))
            }
        }
        if lockNotificationsEnabled && old.lastEvent != new.lastEvent, new.lastEvent == "keyless_lock_disconnect_confirm" {
            changes.append(JL("انقطع BLE — تم تأكيد قفل السيارة مرة ثانية", "BLE disconnected — vehicle lock confirmed again"))
        }
        if old.simulatedDoorsOpen != new.simulatedDoorsOpen {
            changes.append(new.simulatedDoorsOpen ? JL("الباب مفتوح", "Door open") : JL("الأبواب مغلقة", "Doors closed"))
        }
        // Engine start/stop notifications come only from explicit OBD events.
        // Transient OBD timeouts must not generate false shutdown/start alerts.
        if old.remotePowered != new.remotePowered {
            changes.append(new.remotePowered ? JL("الريموت اشتغل", "Remote power on") : JL("الريموت انطفأ بعد تنفيذ المهمة", "Remote power off after the action"))
        }
        if old.headlightsOn != new.headlightsOn {
            changes.append(new.headlightsOn ? JL("اللايت اشتغل", "Lights on") : JL("اللايت انطفأ", "Lights off"))
        }
        if old.leftSignalOn != new.leftSignalOn || old.rightSignalOn != new.rightSignalOn {
            changes.append(signalText(left: new.leftSignalOn, right: new.rightSignalOn))
        }
        if old.hornActive != new.hornActive, new.hornActive {
            changes.append(JL("الإنذار يعمل", "Alarm active"))
        }
        if obdNotificationsEnabled && old.obdConnected != new.obdConnected {
            changes.append(new.obdConnected ? JL("OBD متصل", "OBD connected") : JL("OBD انقطع", "OBD disconnected"))
        }
        if old.online != new.online {
            changes.append(new.online ? JL("السيارة متاحة", "Vehicle online") : JL("اتصال السيارة انقطع", "Vehicle disconnected"))
        }
        if old.diagnosticCodes != new.diagnosticCodes, !new.diagnosticCodes.isEmpty {
            changes.append(JL("ظهر كود فحص جديد", "New diagnostic code detected"))
        }
        if old.coolantC < 105, new.coolantC >= 105 {
            changes.append(JL("تحذير: حرارة المحرك مرتفعة", "Warning: high engine temperature"))
        }
        if old.batteryVoltage >= 11.7, new.batteryVoltage > 0, new.batteryVoltage < 11.7 {
            changes.append(JL("تحذير: بطارية السيارة منخفضة", "Warning: low vehicle battery"))
        }

        guard !changes.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = vehicleName
        content.body = changes.prefix(3).joined(separator: " • ")
        content.sound = .default
        content.threadIdentifier = "journey.vehicle"
        content.categoryIdentifier = "JOURNEY_VEHICLE"

        let request = UNNotificationRequest(
            identifier: "journey.vehicle.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }


    func notifyKeylessDeparture(vehicleName: String, lockDelaySeconds: Int) {
        guard keylessNotificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["journey.keyless.departure"])
        let content = UNMutableNotificationContent()
        content.title = vehicleName
        content.body = JL("ابتعد الهاتف أو انقطع BLE. سيقفل ESP السيارة بعد \(lockDelaySeconds) ثانية إذا لم يرجع اتصال القرب.", "The phone moved away or BLE disconnected. ESP will lock the vehicle after \(lockDelaySeconds) seconds unless proximity returns.")
        content.sound = .default
        content.threadIdentifier = "journey.keyless"
        let request = UNNotificationRequest(identifier: "journey.keyless.departure", content: content, trigger: nil)
        center.add(request)
    }

    func clearKeylessDepartureNotice() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["journey.keyless.departure"])
        center.removeDeliveredNotifications(withIdentifiers: ["journey.keyless.departure"])
    }
    private func signalText(left: Bool, right: Bool) -> String {
        switch (left, right) {
        case (true, true): return JL("الإشارتان تعملان", "Both turn signals active")
        case (true, false): return JL("إشارة اليسار تعمل", "Left turn signal active")
        case (false, true): return JL("إشارة اليمين تعمل", "Right turn signal active")
        case (false, false): return JL("الإشارات انطفأت", "Turn signals off")
        }
    }
}
