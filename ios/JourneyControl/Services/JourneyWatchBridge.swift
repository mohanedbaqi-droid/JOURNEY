import Foundation
import WatchConnectivity

/// Only the paired Apple Watch can request an action; the iPhone keeps
/// credential storage, BLE pairing and MQTT transport. A Watch message
/// NEVER contains credentials or a direct ESP frame.
@MainActor
final class JourneyWatchBridge: NSObject, WCSessionDelegate {
    static let shared = JourneyWatchBridge()

    private let session = WCSession.default
    private var lastPublished: Data?

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

        guard let data = try? JSONEncoder().encode(status) else { return }
        // Application context replaces the previous status if the watch is
        // asleep. Never enqueue unbounded transferUserInfo telemetry traffic.
        if data != lastPublished {
            do {
                try session.updateApplicationContext(["journey.status": data])
                lastPublished = data
            } catch {
                print("[JOURNEY Watch] Could not sync status: \(error.localizedDescription)")
            }
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

        // Never start a physical vehicle directly from the watch: a fresh
        // phone Face ID confirmation is required.
        if action == "start" {
            return ["ok": false, "message": "شغّل من JOURNEY على الآيفون لتأكيد Face ID"]
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
