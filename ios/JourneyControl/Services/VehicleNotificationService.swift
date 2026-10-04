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
        content.body = text.isEmpty ? eventText(for: type) : text
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
        case "engine_started_obd": return "تم تشغيل السيارة"
        case "engine_stopped_obd": return "تم إطفاء السيارة"
        case "coolant_high": return "تحذير: حرارة المحرك مرتفعة"
        case "battery_low": return "تحذير: فولت بطارية السيارة منخفض"
        case "keyless_presence_near": return "اقتربت من السيارة — تم اكتشاف الهاتف"
        case "keyless_presence_far": return "ابتعدت عن السيارة — خرج الهاتف من نطاق القرب"
        case "keyless_unlock": return "اقتربت من السيارة — تم فتح السيارة"
        case "keyless_lock", "keyless_lock_departure": return "ابتعدت عن السيارة — تم قفل السيارة"
        default: return "يوجد تحديث جديد من السيارة"
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
                changes.append("اقتربت من السيارة — تم اكتشاف الهاتف")
            } else if new.lastEvent == "keyless_presence_far" {
                changes.append("ابتعدت عن السيارة — خرج الهاتف من نطاق القرب")
            }
        }
        if lockNotificationsEnabled && old.simulatedLocked != new.simulatedLocked {
            if new.lastEvent == "keyless_unlock" {
                changes.append("اقتربت من السيارة — تم فتح السيارة")
            } else if new.lastEvent == "keyless_lock_departure" || new.lastEvent == "keyless_lock" {
                changes.append("ابتعدت عن السيارة — تم قفل السيارة")
            } else {
                changes.append(new.simulatedLocked ? "تم قفل السيارة" : "تم فتح السيارة")
            }
        }
        if lockNotificationsEnabled && old.lastEvent != new.lastEvent, new.lastEvent == "keyless_lock_disconnect_confirm" {
            changes.append("انقطع BLE — تم تأكيد قفل السيارة مرة ثانية")
        }
        if old.simulatedDoorsOpen != new.simulatedDoorsOpen {
            changes.append(new.simulatedDoorsOpen ? "الباب مفتوح" : "الأبواب مغلقة")
        }
        // Engine start/stop notifications come only from explicit OBD events.
        // Transient OBD timeouts must not generate false shutdown/start alerts.
        if old.remotePowered != new.remotePowered {
            changes.append(new.remotePowered ? "الريموت اشتغل" : "الريموت انطفأ بعد تنفيذ المهمة")
        }
        if old.headlightsOn != new.headlightsOn {
            changes.append(new.headlightsOn ? "اللايت اشتغل" : "اللايت انطفأ")
        }
        if old.leftSignalOn != new.leftSignalOn || old.rightSignalOn != new.rightSignalOn {
            changes.append(signalText(left: new.leftSignalOn, right: new.rightSignalOn))
        }
        if old.hornActive != new.hornActive, new.hornActive {
            changes.append("الإنذار يعمل")
        }
        if obdNotificationsEnabled && old.obdConnected != new.obdConnected {
            changes.append(new.obdConnected ? "OBD متصل" : "OBD انقطع")
        }
        if old.online != new.online {
            changes.append(new.online ? "السيارة متاحة" : "اتصال السيارة انقطع")
        }
        if old.diagnosticCodes != new.diagnosticCodes, !new.diagnosticCodes.isEmpty {
            changes.append("ظهر كود فحص جديد")
        }
        if old.coolantC < 105, new.coolantC >= 105 {
            changes.append("تحذير: حرارة المحرك مرتفعة")
        }
        if old.batteryVoltage >= 11.7, new.batteryVoltage > 0, new.batteryVoltage < 11.7 {
            changes.append("تحذير: بطارية السيارة منخفضة")
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
        content.body = "ابتعد الهاتف أو انقطع BLE. سيقفل ESP السيارة بعد \(lockDelaySeconds) ثانية إذا لم يرجع اتصال القرب."
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
        case (true, true): return "الإشارتان تعملان"
        case (true, false): return "إشارة اليسار تعمل"
        case (false, true): return "إشارة اليمين تعمل"
        case (false, false): return "الإشارات انطفأت"
        }
    }
}
