import SwiftUI

@main
struct JourneyControlApp: App {
    @UIApplicationDelegateAdaptor(JourneyControlAppDelegate.self) private var appDelegate
    @StateObject private var mqtt = MQTTService()
    @StateObject private var proximity = ProximityMonitor()
    @StateObject private var devices = DeviceStore()
    @StateObject private var homeShortcuts = HomeScreenShortcutRouter.shared
    @StateObject private var nfcStore = NFCCredentialStore()
    @StateObject private var nfcRouter = NFCLaunchRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mqtt)
                .environmentObject(proximity)
                .environmentObject(devices)
                .environmentObject(homeShortcuts)
                .environmentObject(nfcStore)
                .environmentObject(nfcRouter)
                .onOpenURL { url in
                    if !nfcRouter.route(url) {
                        _ = homeShortcuts.route(url)
                    }
                }
        }
    }
}
