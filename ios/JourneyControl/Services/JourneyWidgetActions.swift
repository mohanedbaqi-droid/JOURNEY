import Foundation
import LocalAuthentication
import UIKit

@MainActor enum JourneyWidgetActions {
    private static var busy = false
    static func run(_ action: String, deviceID: String) async {
        let devices = DeviceStore()
        let english = UserDefaults.standard.string(forKey: "journey.settings.language") == "en"
        func text(_ ar: String, _ en: String) -> String { english ? en : ar }
        let demo = UserDefaults.standard.bool(forKey: "journey.demo.enabled")
        // Never let a stale Live Activity for a real car control the simulator,
        // or a stale demo activity dispatch a physical vehicle command.
        if demo && deviceID != "journey-demo" {
            JourneyWidgetStore.setStatus(
                deviceID: deviceID,
                message: text("تغيّر وضع التشغيل؛ افتح JOURNEY للتحديث", "Mode changed; open JOURNEY to refresh")
            )
            return
        }
        if !demo {
            guard let device = devices.selectedDevice, device.deviceID == deviceID else {
                JourneyWidgetStore.setStatus(deviceID: deviceID, message: text("تغيّرت السيارة المختارة؛ حدّث الويدجيت", "Selected vehicle changed; refresh the widget"))
                return
            }
        }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if action == "remote_start" {
            for _ in 0..<25 where UIApplication.shared.applicationState != .active { try? await Task.sleep(for: .milliseconds(200)) }
            let context = LAContext()
            context.localizedFallbackTitle = ""
            context.touchIDAuthenticationAllowableReuseDuration = 0
            var error: NSError?
            guard UIApplication.shared.applicationState == .active,
                  context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), context.biometryType == .faceID else {
                JourneyWidgetStore.setStatus(deviceID: deviceID, message: text("Face ID غير متاح؛ لم يُرسل أمر تشغيل", "Face ID unavailable; no start command sent"))
                return
            }
            do {
                guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: text("تأكيد تشغيل سيارة JOURNEY", "Confirm JOURNEY remote start")) else { return }
            } catch {
                JourneyWidgetStore.setStatus(deviceID: deviceID, message: text("لم يتأكد Face ID؛ أُلغي التشغيل", "Face ID not confirmed; start cancelled"))
                return
            }
        }
        let mqtt = MQTTService.shared
        if demo {
            // App Intent controls the shared demo, never the physical vehicle.
            // For remote_start the biometric prompt above has already succeeded.
            switch action {
            case "lock":
                UserDefaults.standard.set(true, forKey: "journey.demo.locked")
            case "unlock":
                UserDefaults.standard.set(false, forKey: "journey.demo.locked")
            case "remote_start":
                let running = UserDefaults.standard.bool(forKey: "journey.demo.engine")
                UserDefaults.standard.set(!running, forKey: "journey.demo.engine")
            case "refresh": break
            default: return
            }
            mqtt.syncSelectedWidget(force: true)
            JourneyWidgetStore.setStatus(deviceID: "journey-demo", message: text("تحديث تجريبي — لم يُرسل أمر للسيارة", "Demo updated — no vehicle command sent"))
            return
        }
        let baseline = mqtt.lastStateAt[deviceID]
        mqtt.prepareBluetooth(for: deviceID)
        if mqtt.isConfigured && mqtt.connection != .connected { mqtt.connect() }
        JourneyWidgetStore.setStatus(deviceID: deviceID, message: text("جاري الاتصال بـESP…", "Connecting to ESP…"))
        var fresh = false
        var requestedState = false
        for _ in 0..<60 {
            if !requestedState && mqtt.sendESPCommand(VehicleCommand(action: .ownerStatus), to: deviceID) { requestedState = true }
            if let date = mqtt.lastStateAt[deviceID], date != baseline, Date().timeIntervalSince(date) < 4, mqtt.state(for: deviceID).online { fresh = true; break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard fresh else {
            JourneyWidgetStore.setStatus(deviceID: deviceID, message: text("ESP غير متصل؛ لم يُرسل أمر", "ESP unavailable; no command sent"))
            mqtt.syncSelectedWidget(force: true)
            return
        }
        if action == "refresh" {
            mqtt.syncSelectedWidget(force: true)
            JourneyWidgetStore.setStatus(deviceID: deviceID, message: text("وصلت قراءة جديدة من ESP", "New ESP reading received"))
            return
        }
        guard DeviceStore().selectedDevice?.deviceID == deviceID else {
            JourneyWidgetStore.setStatus(deviceID: deviceID, message: text("تغيّرت السيارة؛ أُلغي الأمر", "Vehicle changed; command cancelled"))
            return
        }
        guard let command = BenchAction(rawValue: action), [.lock, .unlock, .start].contains(command), mqtt.send(command, to: deviceID) else {
            JourneyWidgetStore.setStatus(deviceID: deviceID, message: text("تعذر إرسال الأمر", "Could not send command"))
            return
        }
        // A transport write is not proof of lock position or engine start.
        JourneyWidgetStore.setStatus(deviceID: deviceID, message: text("أُرسل الطلب؛ الحالة تعتمد على قراءة السيارة", "Request sent; status comes from vehicle readings"))
        try? await Task.sleep(for: .seconds(2))
        mqtt.syncSelectedWidget(force: true)
    }
}
