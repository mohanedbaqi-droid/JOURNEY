import SwiftUI

@main
struct PunisherDriveApp: App {
    @StateObject private var garage = VehicleProfileStore()
    @State private var showingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(garage)
                    .opacity(showingSplash ? 0 : 1)

                if showingSplash {
                    LaunchSplashView()
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(1150))
                withAnimation(.easeOut(duration: 0.35)) {
                    showingSplash = false
                }
            }
        }
    }
}
