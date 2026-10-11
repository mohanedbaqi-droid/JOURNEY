import AppIntents
import Foundation

struct JourneyLockIntent: AppIntent {
    static var title: LocalizedStringResource = "قفل سيارة JOURNEY"
    static var openAppWhenRun = false
    static var isDiscoverable = false
    @Parameter(title: "Vehicle") var deviceID: String
    init() { deviceID = "" }
    init(deviceID: String) { self.deviceID = deviceID }
    @MainActor func perform() async throws -> some IntentResult {
        if JourneyWidgetStore.read()?.demoMode == true {
            _ = JourneyWidgetStore.applyDemoLock(true)
        } else {
            #if JOURNEY_APP
            await JourneyWidgetActions.run("lock", deviceID: deviceID)
            #else
            // The extension must never send a physical vehicle command.
            // Live-car controls use a deep link to the enrolled host app.
            JourneyWidgetStore.setStatus(deviceID: deviceID, message: "افتح JOURNEY للتحكم بالسيارة الحقيقية")
            #endif
        }
        return .result()
    }
}
struct JourneyUnlockIntent: AppIntent {
    static var title: LocalizedStringResource = "فتح سيارة JOURNEY"
    static var openAppWhenRun = false
    static var isDiscoverable = false
    @Parameter(title: "Vehicle") var deviceID: String
    init() { deviceID = "" }
    init(deviceID: String) { self.deviceID = deviceID }
    @MainActor func perform() async throws -> some IntentResult {
        if JourneyWidgetStore.read()?.demoMode == true {
            _ = JourneyWidgetStore.applyDemoLock(false)
        } else {
            #if JOURNEY_APP
            await JourneyWidgetActions.run("unlock", deviceID: deviceID)
            #else
            JourneyWidgetStore.setStatus(deviceID: deviceID, message: "افتح JOURNEY للتحكم بالسيارة الحقيقية")
            #endif
        }
        return .result()
    }
}
struct JourneyStartIntent: AppIntent {
    static var title: LocalizedStringResource = "تشغيل JOURNEY بعد Face ID"
    // Fresh biometric authorization requires the app's foreground authentication UI.
    static var openAppWhenRun = true
    static var isDiscoverable = false
    @Parameter(title: "Vehicle") var deviceID: String
    init() { deviceID = "" }
    init(deviceID: String) { self.deviceID = deviceID }
    @MainActor func perform() async throws -> some IntentResult {
        #if JOURNEY_APP
        await JourneyWidgetActions.run("remote_start", deviceID: deviceID)
        #endif
        return .result()
    }
}
struct JourneyRefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "تحديث بيانات JOURNEY"
    static var openAppWhenRun = false
    static var isDiscoverable = false
    @Parameter(title: "Vehicle") var deviceID: String
    init() { deviceID = "" }
    init(deviceID: String) { self.deviceID = deviceID }
    @MainActor func perform() async throws -> some IntentResult {
        #if JOURNEY_APP
        await JourneyWidgetActions.run("refresh", deviceID: deviceID)
        #else
        JourneyWidgetStore.setStatus(deviceID: deviceID, message: "تعذر التحديث بالخلفية؛ راجع توقيع التطبيق والويدجيت")
        #endif
        return .result()
    }
}
#if JOURNEY_APP
// App-process execution reuses the enrolled phone identity and its existing BLE connection.
extension JourneyLockIntent: ForegroundContinuableIntent {}
extension JourneyUnlockIntent: ForegroundContinuableIntent {}
extension JourneyRefreshIntent: ForegroundContinuableIntent {}
#endif
