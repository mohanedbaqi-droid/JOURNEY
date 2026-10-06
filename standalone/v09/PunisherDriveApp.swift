import SwiftUI

@main
struct PunisherDriveApp: App {
    @StateObject private var garage = VehicleProfileStore()
    @State private var showingSplash = true
    @AppStorage(PDLocalization.key) private var language = "ar"

    private var selectedLanguage: PDLanguage {
        PDLanguage(rawValue: language) ?? .ar
    }

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
            .environment(\.layoutDirection, selectedLanguage.isRTL ? .rightToLeft : .leftToRight)
            .id(language)
            .task {
                try? await Task.sleep(for: .milliseconds(1150))
                withAnimation(.easeOut(duration: 0.35)) {
                    showingSplash = false
                }
            }
        }
    }
}
