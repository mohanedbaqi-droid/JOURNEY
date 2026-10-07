import Foundation
import LocalAuthentication
import UIKit

@MainActor enum JourneyWidgetActions {
    private static var busy = false
    static func run(_ action: String, deviceID: String) async {
        let devices = DeviceStore()
        let english = UserDefaults.standard.string(forKey: "journey.settings.language") == "en"
        func text(_ ar: String, _ en: String) -> String { english ? en : ar }
        guard let device = devices.selectedDevice, device.deviceID == deviceID else {
            JourneyWidgetStore.setStatus(deviceID: deviceID, message: text("تغيّرت السيارة المختارة؛ حدّث الويدجيت", "Selected vehicle changed; refresh the widget"))
            return
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
        let baseline = mqtt.lastStateAt[deviceID]
        mqtt.prepareBluetooth(for: deviceID)
        if mqtt.isConfigured && mqtt.connection != .connected { mqtt.connect() }
        JourneyWidgetStore.setStatus(deviceID: deviceID, message: text("جاري الاتصال بـESP…", "Connecting to ESP…"))
        var fresh = false
        for _ in 0..<40 {
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
