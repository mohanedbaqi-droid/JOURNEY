import SwiftUI

struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.005, blue: 0.015), Color(red: 0.0, green: 0.055, blue: 0.085)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.red.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 110)
                .offset(x: -160, y: -180)

            Circle()
                .fill(.cyan.opacity(0.16))
                .frame(width: 430, height: 430)
                .blur(radius: 120)
                .offset(x: 160, y: 150)

            VStack(spacing: 18) {
                Spacer()
                Image("PunisherMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 270, height: 270)
                    .shadow(color: .red.opacity(0.45), radius: 24)
                    .shadow(color: .cyan.opacity(0.25), radius: 18)

                VStack(spacing: 1) {
                    Text("PUNISHER")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .italic()
                        .foregroundStyle(
                            LinearGradient(colors: [.white, .red], startPoint: .top, endPoint: .bottom)
                        )
                    Text("DRIVE")
                        .font(.system(size: 43, weight: .black, design: .rounded))
                        .italic()
                        .foregroundStyle(
                            LinearGradient(colors: [.white, .cyan], startPoint: .top, endPoint: .bottom)
                        )
                }

                Text("SMART VEHICLE CONTROL")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(3.0)
                    .foregroundStyle(.white.opacity(0.72))

                Spacer()
                HStack(spacing: 26) {
                    Image(systemName: "location.fill")
                    Image(systemName: "lock.fill")
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Image(systemName: "touchid")
                }
                .font(.headline)
                .foregroundStyle(.cyan.opacity(0.65))
                .padding(.bottom, 38)
            }
        }
        .preferredColorScheme(.dark)
    }
}
