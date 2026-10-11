import Foundation
import WatchConnectivity
import UserNotifications

/// Only the paired Apple Watch can request an action; the iPhone keeps
/// credential storage, BLE pairing and MQTT transport. A Watch message
/// NEVER contains credentials or a direct ESP frame.
@MainActor
final class JourneyWatchBridge: NSObject, WCSessionDelegate {
    static let shared = JourneyWatchBridge()

    private let session = WCSession.default
    private var lastPublished: Data?
    private var lastVehicle: JourneyWatchStatus?
    private var lastPublishedAt = Date.distantPast

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        if session.activationState == .notActivated {
            session.activate()
        }
    }

    func publish(_ snapshot: JourneyWidgetSnapshot) {
        guard WCSession.isSupported() else { return }
        activate()
        guard session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }

        let status = JourneyWatchStatus(
            deviceID: snapshot.deviceID,
            vehicleName: snapshot.name,
            demoMode: snapshot.demoMode,
            online: snapshot.online,
            locked: snapshot.locked,
            running: snapshot.rpm.map { $0 > 0 },
            rpm: snapshot.rpm,
            speedKph: snapshot.speed,
            coolantC: snapshot.coolant,
            vehicleBattery: snapshot.battery,
            doorKnownMask: snapshot.doorKnownMask,
            doorOpenMask: snapshot.doorOpenMask,
            headlights: snapshot.lowBeam,
            leftTurn: snapshot.leftTurn,
            rightTurn: snapshot.rightTurn,
            readingAt: snapshot.stateAt,
            transferredAt: Date()
        )

        let now = Date()
        if let previous = lastVehicle {
            let criticalChanged =
                previous.demoMode != status.demoMode ||
                previous.deviceID != status.deviceID ||
                previous.online != status.online ||
                previous.locked != status.locked ||
                previous.running != status.running ||
                previous.doorOpenMask != status.doorOpenMask ||
                previous.doorKnownMask != status.doorKnownMask ||
                previous.headlights != status.headlights ||
                previous.leftTurn != status.leftTurn ||
                previous.rightTurn != status.rightTurn
            // RPM/GPS heartbeat changes must not queue an iPhone-to-watch
            // transfer every second. Always send critical controls promptly.
            if !criticalChanged && now.timeIntervalSince(lastPublishedAt) < 8 { return }
        }

        guard let data = try? JSONEncoder().encode(status) else { return }
        do {
            // updateApplicationContext keeps only the latest state for a
            // sleeping watch; unlike transferUserInfo it cannot pile up.
            try session.updateApplicationContext(["journey.status": data])
            lastPublished = data
            lastVehicle = status
            lastPublishedAt = now
        } catch {
            print("[JOURNEY Watch] Could not sync status: \(error.localizedDescription)")
        }
    }

    private func perform(_ message: [String: Any]) -> [String: Any] {
        guard let type = message["type"] as? String else {
            return ["ok": false, "message": "طلب غير صالح"]
        }
        if type == "refresh" {
            MQTTService.shared.syncSelectedWidget(force: true)
            return ["ok": true, "message": "جاري تحديث القراءة"]
        }
        guard type == "command",
              let action = message["action"] as? String,
              ["lock", "unlock", "start"].contains(action),
              let deviceID = message["deviceID"] as? String,
              !deviceID.isEmpty else {
            return ["ok": false, "message": "الأمر غير معروف"]
        }

        // Watch start is a request to open the iPhone confirmation UI, never
        // a direct engine command. A local notification supports both demo
        // and live modes without granting the watch permission to start.
        if action == "start" {
            let content = UNMutableNotificationContent()
            content.title = "JOURNEY — Apple Watch"
            content.body = "طلب تشغيل من الساعة. افتح التطبيق وأكد باستخدام Face ID."
            content.sound = .default
            content.userInfo = ["journey.watch.startRequest": true]
            let request = UNNotificationRequest(
                identifier: "journey.watch.start.(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
            return ["ok": true, "message": "تفقد إشعار JOURNEY على الآيفون لتأكيد Face ID"]
        }

        let defaults = UserDefaults.standard
        let demoMode = defaults.bool(forKey: "journey.demo.enabled")
        if demoMode {
            guard deviceID == "journey-demo" else {
                return ["ok": false, "message": "تغيّر الوضع؛ حدّث الساعة"]
            }
            defaults.set(action == "lock", forKey: "journey.demo.locked")
            MQTTService.shared.syncSelectedWidget(force: true)
            return ["ok": true, "message": action == "lock" ? "انقفل بالديمو" : "انفتح بالديمو"]
        }

        let devices = DeviceStore()
        guard let selected = devices.selectedDevice,
              selected.deviceID == deviceID,
              let freshAt = MQTTService.shared.lastStateAt[deviceID],
              Date().timeIntervalSince(freshAt) >= 0,
              Date().timeIntervalSince(freshAt) < 6,
              MQTTService.shared.state(for: deviceID).online else {
            return ["ok": false, "message": "السيارة غير متصلة؛ لم يُرسل أي أمر"]
        }

        let command: BenchAction = action == "lock" ? .lock : .unlock
        guard MQTTService.shared.send(command, to: deviceID) else {
            return ["ok": false, "message": "تعذّر إرسال الأمر للـ ESP"]
        }
        // Sending over a transport does not prove the doors actually locked.
        return ["ok": true, "message": "أُرسل الطلب؛ ننتظر تأكيد السيارة"]
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated {
            Task { @MainActor in
                MQTTService.shared.syncSelectedWidget(force: true)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in self.activate() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in MQTTService.shared.syncSelectedWidget(force: true) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            let response = self.perform(message)
            replyHandler(response)
        }
    }
}
